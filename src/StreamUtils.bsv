import Vector::*;
import FIFOF::*;
import GetPut::*;
import Connectable::*;
import SemiFifo::*;

import BdmaPrimUtils::*;
import DmaTypes::*;
import PcieAxiStreamTypes::*;

typedef 32 STREAM_SIZE_WIDTH;
typedef UInt#(STREAM_SIZE_WIDTH) StreamSize;
typedef Bit#(TAdd#(1, TLog#(STREAM_SIZE_WIDTH))) StreamSizeBitPtr;

typedef struct {
    DataStream stream;
    DataBytePtr bytePtr;
} StreamWithPtr deriving(Bits, Bounded, Eq, FShow);

interface StreamPipe;
    interface FifoIn#(DataStream)  streamFifoIn;
    interface FifoOut#(DataStream) streamFifoOut;
endinterface

interface StreamSplit;
    interface FifoIn#(DataStream)  inputStreamFifoIn;
    interface FifoIn#(StreamSize)  splitLocationFifoIn;
    interface FifoOut#(DataStream) outputStreamFifoOut;
endinterface

function Bool isByteEnZero(ByteEn byteEn);
    return !unpack(byteEn[0]);
endfunction

function Bool isByteEnFull(ByteEn byteEn);
    return unpack(byteEn[valueOf(BYTE_EN_WIDTH)-1]);
endfunction

function DataStream getEmptyStream ();
    return DataStream {
        data: 0,
        byteEn: 0,
        isFirst: False,
        isLast: True
    };
endfunction

function StreamWithPtr getEmptyStreamWithPtr ();
    return StreamWithPtr {
        stream : getEmptyStream,
        bytePtr: 0
    };
endfunction

function DataBitPtr getMaxBitPtr ();
    return fromInteger(valueOf(DATA_WIDTH));
endfunction

function DataBytePtr getMaxBytePtr ();
    return fromInteger(valueOf(BYTE_EN_WIDTH));
endfunction

// Concat two DataStream frames into one. StreamA.isLast must be True, otherwise the function will return a empty frame to end the stream.
function Tuple2#(StreamWithPtr, StreamWithPtr) getConcatStream (StreamWithPtr streamA, StreamWithPtr streamB);
    Bool isCallLegally = (streamA.stream.isLast && streamA.bytePtr <= getMaxBytePtr && streamA.bytePtr >= 0);
    DataBitPtr bitPtrA = zeroExtend(streamA.bytePtr) << fromInteger(valueOf(BYTE_WIDTH_WIDTH));

    // Fill the low PtrA bytes by streamA data
    Data   concatDataA   = streamA.stream.data;
    ByteEn concatByteEnA = streamA.stream.byteEn;

    // Fill the high bytes by streamB data
    Data   concatDataB   = streamB.stream.data   << bitPtrA;
    ByteEn concatByteEnB = streamB.stream.byteEn << streamA.bytePtr;
    Data   concatData    = concatDataA   | concatDataB;
    ByteEn concatByteEn  = concatByteEnA | concatByteEnB;

    // Get the remain bytes of streamB data
    DataBitPtr  resBitPtr    = getMaxBitPtr  - bitPtrA;
    DataBytePtr resBytePtr   = getMaxBytePtr - streamA.bytePtr;
    Data        remainData   = streamB.stream.data   >> resBitPtr;
    ByteEn      remainByteEn = streamB.stream.byteEn >> resBytePtr;

    // Get if the concat frame is the last, i.e. can streamB be contained by the residual empty bytes
    Bool        isConcatStreamLast = streamB.stream.isLast;
    DataBytePtr remainBytePtr      = 0;
    DataBytePtr concatStreamPtr    = streamA.bytePtr;
    if (resBytePtr < streamB.bytePtr ) begin    
        isConcatStreamLast = False;
        remainBytePtr      = streamB.bytePtr - resBytePtr;
        concatStreamPtr    = getMaxBytePtr;
    end
    else begin
        concatStreamPtr    = streamA.bytePtr + streamB.bytePtr;
    end

    // package the return concatStream and remainStream
    DataStream concatStream = getEmptyStream;
    DataStream remainStream = getEmptyStream;
    if(isCallLegally) begin
        concatStream = DataStream {
            data   : concatData,
            byteEn : concatByteEn,
            isFirst: streamA.stream.isFirst,
            isLast : isConcatStreamLast
        };
        remainStream = DataStream {
            data   : remainData,
            byteEn : remainByteEn,
            isFirst: False,
            isLast : True
        };
    end
    let concatStreamWithPtr = StreamWithPtr {
        stream : concatStream,
        bytePtr: concatStreamPtr
    };
    let remainStreamWithPtr = StreamWithPtr {
        stream : remainStream,
        bytePtr: remainBytePtr
    };
    return tuple2(concatStreamWithPtr, remainStreamWithPtr);
endfunction

typedef 5 STREAM_SPLIT_LATENCY;
typedef 3 STREAM_SPLIT_INNER_LATENCY;

module mkStreamSplit(StreamSplit ifc);

    Reg#(StreamSize) streamByteCntReg <- mkReg(0);

    FIFOF#(StreamSize)    splitLocationFifo <- mkSizedFIFOF(valueOf(STREAM_SPLIT_INNER_LATENCY));
    FIFOF#(DataStream)    inputFifo         <- mkFIFOF;
    FIFOF#(DataStream)    outputFifo        <- mkFIFOF;
    FIFOF#(StreamWithPtr) prepareFifo       <- mkFIFOF;
    FIFOF#(StreamWithPtr) assertFifo        <- mkFIFOF;
    FIFOF#(DataBytePtr)   splitPtrFifo      <- mkSizedFIFOF(valueOf(STREAM_SPLIT_INNER_LATENCY));

    Reg#(StreamWithPtr)   remainStreamWpReg <- mkRegU;

    Reg#(Bool) hasRemainReg     <- mkReg(False);
    Reg#(Bool) hasLastRemainReg <- mkReg(False);
    Reg#(Bool) isSplittedReg    <- mkReg(False);
    
    // Pipeline stage 1: get the bytePtr of the input stream frame
    rule prepareStream;
        let stream = inputFifo.first;
        inputFifo.deq;
        StreamWithPtr streamWithPtr = StreamWithPtr {
            stream: stream,
            bytePtr: convertByteEn2BytePtr(stream.byteEn) 
        };
        prepareFifo.enq(streamWithPtr);
    endrule

    // Pipeline stage 2: assert if splitLocation in this beat and calculate the offsetBytePtr
    rule assertSplitStream;
        let stream = prepareFifo.first.stream;
        let bytePtr = prepareFifo.first.bytePtr;       
        prepareFifo.deq; 
        let splitLocation = splitLocationFifo.first;
        if (stream.isLast) begin
            splitLocationFifo.deq;
        end
        DataBytePtr offsetBytePtr = 0;
        let curLocation = unpack(zeroExtend(bytePtr)) + streamByteCntReg;
        if (!isSplittedReg) begin
            if (curLocation > splitLocation) begin
                offsetBytePtr = truncate(pack(splitLocation - streamByteCntReg));
            end
            else if (curLocation == splitLocation) begin
                offsetBytePtr = bytePtr;
            end
        end
        // $display($time, "ns SIM INFO @ mkStreamSplit: curLocation:%d, splitLocation:%d, offset:%d", curLocation, splitLocation, offsetBytePtr);
        splitPtrFifo.enq(offsetBytePtr);
        if (offsetBytePtr > 0 && !stream.isLast) begin
            isSplittedReg <= True;
        end 
        else if (stream.isLast) begin
            isSplittedReg <= False;
        end
        streamByteCntReg <= stream.isLast ? 0 : streamByteCntReg + unpack(zeroExtend(bytePtr));
        assertFifo.enq(prepareFifo.first);
    endrule

    // Pipeline stage 3: split the stream frame or output it without modify accroding to offsetBytePtr
    rule execSplitStream;
        // Only output remainStreamReg
        if (hasRemainReg && hasLastRemainReg) begin
            outputFifo.enq(remainStreamWpReg.stream);
            hasRemainReg <= False;
            hasLastRemainReg <= False;
        end
        // not the last remain stream
        else if (assertFifo.notEmpty && splitPtrFifo.notEmpty) begin
            let streamWp = assertFifo.first;
            let offsetBytePtr = splitPtrFifo.first;
            assertFifo.deq;
            splitPtrFifo.deq;
            // split location not in this beat, do nothing
            if (!hasRemainReg && offsetBytePtr == 0) begin
                outputFifo.enq(streamWp.stream);
                hasRemainReg     <= False;
                hasLastRemainReg <= False;
            end
            // split the frame in this cycle to a isLast=True frame and a remain frame
            else if (!hasRemainReg && offsetBytePtr > 0) begin
                DataBitPtr offsetBitPtr = zeroExtend(offsetBytePtr) << valueOf(BYTE_WIDTH_WIDTH);
                let splitStream = DataStream {
                    data: getDataLowBytes(streamWp.stream.data, offsetBytePtr),
                    byteEn: convertBytePtr2ByteEn(offsetBytePtr),
                    isFirst: streamWp.stream.isFirst,
                    isLast: True
                };
                outputFifo.enq(splitStream);
                let remainStream = DataStream {
                    data: streamWp.stream.data >> offsetBitPtr,
                    byteEn: streamWp.stream.byteEn >> offsetBytePtr,
                    isFirst: True,
                    isLast: True
                };
                hasRemainReg      <= streamWp.stream.isLast ? !isByteEnZero(remainStream.byteEn) : True;
                hasLastRemainReg  <= streamWp.stream.isLast;
                remainStreamWpReg <= StreamWithPtr {
                    stream : remainStream,
                    bytePtr: streamWp.bytePtr - offsetBytePtr
                };
            end
            // concat the stream frame with the remainReg
            else begin
                let {concatStreamWp, remainStreamWp} = getConcatStream(remainStreamWpReg, streamWp);
                outputFifo.enq(concatStreamWp.stream);
                hasRemainReg     <= streamWp.stream.isLast ? !isByteEnZero(remainStreamWp.stream.byteEn) : True;
                hasLastRemainReg <= streamWp.stream.isLast;
                remainStreamWpReg <= remainStreamWp;
            end
        end
    endrule

    interface inputStreamFifoIn   = convertFifoToFifoIn(inputFifo);
    interface splitLocationFifoIn = convertFifoToFifoIn(splitLocationFifo);
    interface outputStreamFifoOut = convertFifoToFifoOut(outputFifo);

endmodule

typedef 2 STREAM_SHIFT_LATENCY;

module mkStreamShift#(DataBytePtr offset)(StreamPipe);
    FIFOF#(DataStream) inFifo  <- mkFIFOF;
    FIFOF#(DataStream) outFifo <- mkFIFOF;

    DataBytePtr resByte    = getMaxBytePtr - offset;
    DataBitPtr  offsetBits = zeroExtend(offset) << valueOf(BYTE_WIDTH_WIDTH);
    DataBitPtr  resBits    = getMaxBitPtr - offsetBits;

    Reg#(DataStream) remainStreamReg <- mkReg(getEmptyStream);
    Reg#(Bool)  hasLastRemainReg <- mkReg(False);

    function Bool isShiftStreamLast(DataStream stream);
        Bool isLast = False;
        if (offset > 0 && offset < getMaxBytePtr) begin
            isLast = stream.isLast && !unpack(stream.byteEn[resByte]);
        end
        else if (offset == 0) begin
            isLast = stream.isLast;
        end
        else begin
            isLast = False;
        end
        return isLast;
    endfunction

    rule execShift;
        if (hasLastRemainReg) begin
            outFifo.enq(remainStreamReg);
            hasLastRemainReg <= False;
            remainStreamReg <= getEmptyStream;
        end
        else begin
            let stream = inFifo.first;
            inFifo.deq;
            let shiftStream = DataStream {
                data    : (stream.data << offsetBits) | remainStreamReg.data,
                byteEn  : (stream.byteEn << offset)   | remainStreamReg.byteEn,
                isFirst : stream.isFirst,
                isLast  : isShiftStreamLast(stream)
            };
            let remainStream = DataStream {
                data    : stream.data >> resBits,
                byteEn  : stream.byteEn >> resByte,
                isFirst : False,
                isLast  : True
            };
            outFifo.enq(shiftStream);
            remainStreamReg  <= remainStream;
            hasLastRemainReg <= stream.isLast && !isByteEnZero(remainStream.byteEn);
        end
    endrule

    interface streamFifoIn  = convertFifoToFifoIn(inFifo);
    interface streamFifoOut = convertFifoToFifoOut(outFifo);
endmodule

interface StreamShiftComplex;
    interface FifoIn#(DataStream)  streamFifoIn;
    interface FifoOut#(Tuple2#(DataStream, DataStream)) streamFifoOut;
endinterface

module mkStreamShiftComplex#(DataBytePtr offset)(StreamShiftComplex);
    FIFOF#(DataStream) inFifo  <- mkFIFOF;
    FIFOF#(Tuple2#(DataStream, DataStream)) outFifo <- mkFIFOF;

    DataBytePtr resByte    = getMaxBytePtr - offset;
    DataBitPtr  offsetBits = zeroExtend(offset) << valueOf(BYTE_WIDTH_WIDTH);
    DataBitPtr  resBits    = getMaxBitPtr - offsetBits;

    Reg#(DataStream) remainStreamReg <- mkReg(getEmptyStream);
    Reg#(Bool)  hasLastRemainReg <- mkReg(False);

    function Bool isShiftStreamLast(DataStream stream);
        Bool isLast = False;
        if (offset > 0 && offset < getMaxBytePtr) begin
            isLast = stream.isLast && !unpack(stream.byteEn[resByte]);
        end
        else if (offset == 0) begin
            isLast = stream.isLast;
        end
        else begin
            isLast = False;
        end
        return isLast;
    endfunction

    rule execShift;
        if (hasLastRemainReg) begin
            outFifo.enq(tuple2(getEmptyStream, remainStreamReg));
            hasLastRemainReg <= False;
            remainStreamReg <= getEmptyStream;
        end
        else begin
            let stream = inFifo.first;
            inFifo.deq;
            let shiftStream = DataStream {
                data    : (stream.data << offsetBits) | remainStreamReg.data,
                byteEn  : (stream.byteEn << offset)   | remainStreamReg.byteEn,
                isFirst : stream.isFirst,
                isLast  : isShiftStreamLast(stream)
            };
            let remainStream = DataStream {
                data    : stream.data >> resBits,
                byteEn  : stream.byteEn >> resByte,
                isFirst : False,
                isLast  : True
            };
            outFifo.enq(tuple2(stream, shiftStream));
            remainStreamReg  <= remainStream;
            hasLastRemainReg <= stream.isLast && !isByteEnZero(remainStream.byteEn);
        end
    endrule

    interface streamFifoIn  = convertFifoToFifoIn(inFifo);
    interface streamFifoOut = convertFifoToFifoOut(outFifo);
endmodule

typedef enum {
    Align0 = 0,
    Align1 = 1,
    Align2 = 2,
    Align3 = 3
} AlignDwMode deriving(Bits, Eq, Bounded, FShow);

interface StreamShiftAlignToDw;
    interface FifoIn#(DataStream)        dataFifoIn;
    interface FifoOut#(DataStream)       dataFifoOut;
    method Action setAlignMode(AlignDwMode align);
endinterface

typedef 2 STREAM_ALIGN_DW_LATENCY;

module mkStreamShiftAlignToDw#(DataBytePtr offset)(StreamShiftAlignToDw);
    FIFOF#(DataStream) dataInFifo     <- mkFIFOF;
    // FIFOF#(DataStream) pipeFifo       <- mkFIFOF;
    FIFOF#(DataStream) dataOutFifo    <- mkFIFOF;
    FIFOF#(AlignDwMode) alignModeFifo <- mkFIFOF;

    Reg#(DataStream)   remainStreamReg  <- mkReg(getEmptyStream);
    Reg#(Bool)         hasLastRemainReg <- mkReg(False);

    DataBytePtr resByte    = getMaxBytePtr - (offset + 3);
    DataBitPtr  offsetBits = zeroExtend(offset) << valueOf(BYTE_WIDTH_WIDTH);
    DataBitPtr  resBits    = zeroExtend(resByte) << valueOf(BYTE_WIDTH_WIDTH);
    ByteEn byteEnMask1 = 1 << (offset);
    ByteEn byteEnMask2 = 1 << (offset + 1) | byteEnMask1 ;
    ByteEn byteEnMask3 = 1 << (offset + 2) | byteEnMask2;
    
    // rule pipe;
    //     pipeFifo.enq(dataInFifo.first);
    //     dataInFifo.deq;
    // endrule

    rule execShift;
        if (hasLastRemainReg) begin
            dataOutFifo.enq(remainStreamReg);
            hasLastRemainReg <= False;
            remainStreamReg <= getEmptyStream;
        end
        else begin
            // let stream = pipeFifo.first;
            // pipeFifo.deq;
            let stream = dataInFifo.first;
            dataInFifo.deq;
            let shiftStream = DataStream {
                data    : stream.data << offsetBits,
                byteEn  : stream.byteEn << offset  ,
                isFirst : stream.isFirst,
                isLast  : stream.isLast
            };
            let remainStream = DataStream {
                data    : stream.data >> resBits,
                byteEn  : stream.byteEn >> resByte,
                isFirst : False,
                isLast  : True
            };
            let alignMode = alignModeFifo.first;
            if (stream.isLast) begin
                alignModeFifo.deq;
            end
            case (alignMode)
                Align1: begin
                    shiftStream.data    = shiftStream.data << valueOf(TMul#(1, BYTE_WIDTH)) | remainStreamReg.data;
                    shiftStream.byteEn  = shiftStream.byteEn << 1 | byteEnMask1 | remainStreamReg.byteEn;
                    remainStream.data   = remainStream.data >> valueOf(TMul#(2, BYTE_WIDTH));
                    remainStream.byteEn = remainStream.byteEn >> 2;
                end
                Align2: begin
                    shiftStream.data = shiftStream.data << valueOf(TMul#(2, BYTE_WIDTH)) | remainStreamReg.data;
                    shiftStream.byteEn = shiftStream.byteEn << 2 | byteEnMask2 | remainStreamReg.byteEn;
                    remainStream.data   = remainStream.data >> valueOf(TMul#(1, BYTE_WIDTH));
                    remainStream.byteEn = remainStream.byteEn >> 1;
                end
                Align3: begin
                    shiftStream.data = shiftStream.data << valueOf(TMul#(3, BYTE_WIDTH)) | remainStreamReg.data;
                    shiftStream.byteEn = shiftStream.byteEn << 3 | byteEnMask3 | remainStreamReg.byteEn;
                    remainStream.data   = remainStream.data;
                    remainStream.byteEn = remainStream.byteEn;
                end
                default: begin
                    shiftStream.data = shiftStream.data | remainStreamReg.data;
                    shiftStream.byteEn = shiftStream.byteEn | remainStreamReg.byteEn;
                    remainStream.data   = remainStream.data >> valueOf(TMul#(3, BYTE_WIDTH));
                    remainStream.byteEn = remainStream.byteEn >> 3;
                end
            endcase
            shiftStream.isLast = shiftStream.isLast && isByteEnZero(remainStream.byteEn);
            dataOutFifo.enq(shiftStream);
            remainStreamReg  <= remainStream;
            hasLastRemainReg <= stream.isLast && !isByteEnZero(remainStream.byteEn);
        end
    endrule

    method Action setAlignMode(AlignDwMode align);
        alignModeFifo.enq(align);
    endmethod

    interface dataFifoIn    = convertFifoToFifoIn(dataInFifo);
    interface dataFifoOut   = convertFifoToFifoOut(dataOutFifo);
endmodule

typedef 3 STREAM_HEADER_REMOVE_LATENCY;

// Remove the first N Bytes of a stream
module mkStreamHeaderRemove#(DataBytePtr headerLen)(StreamPipe);
    FIFOF#(DataStream) inFifo  <- mkFIFOF;
    FIFOF#(DataStream) outFifo <- mkFIFOF;

    Reg#(DataStream) remainStreamReg  <- mkReg(getEmptyStream);
    Reg#(Bool)       hasLastRemainReg <- mkReg(False);

    DataBitPtr  headerBitLen = zeroExtend(headerLen) << valueOf(BYTE_WIDTH_WIDTH);
    DataBytePtr shiftLen = getMaxBytePtr -  headerLen;
    DataBitPtr  shiftBitLen = zeroExtend(shiftLen) << valueOf(BYTE_WIDTH_WIDTH);

    rule removeHeader;
        if (hasLastRemainReg) begin
            outFifo.enq(remainStreamReg);
            hasLastRemainReg <= False;
            remainStreamReg <= getEmptyStream;
        end
        else begin
            let stream = inFifo.first;
            inFifo.deq;
            let remainStream = DataStream {
                data    : stream.data >> headerBitLen,
                byteEn  : stream.byteEn >> headerLen,
                isFirst : stream.isFirst,
                isLast  : stream.isLast
            };
            let newStream = DataStream {
                data    : remainStreamReg.data | stream.data << shiftBitLen,
                byteEn  : remainStreamReg.byteEn | stream.byteEn << shiftLen,
                isFirst : remainStreamReg.isFirst,
                isLast  : isByteEnZero(remainStream.byteEn)
            };
            
            if (stream.isLast && stream.isFirst) begin 
                outFifo.enq(remainStream);
                hasLastRemainReg <= False;
                remainStreamReg <= getEmptyStream;
            end
            else if (stream.isFirst) begin
                remainStreamReg <= remainStream;
            end
            else begin
                outFifo.enq(newStream);
                if (stream.isLast) begin    
                    if(isByteEnZero(remainStream.byteEn)) begin
                        remainStreamReg <= getEmptyStream;
                        hasLastRemainReg <= False;
                    end
                    else begin
                        remainStreamReg <= remainStream;
                        hasLastRemainReg <= True;
                    end
                end
                else begin
                    remainStreamReg <= remainStream;
                end
            end
        end
    endrule

    interface streamFifoIn  = convertFifoToFifoIn(inFifo);
    interface streamFifoOut = convertFifoToFifoOut(outFifo);
endmodule

// Only support one not full dataStream between streams
module mkStreamReshape(StreamPipe);
    FIFOF#(DataStream) inFifo  <- mkFIFOF;
    FIFOF#(DataStream) outFifo <- mkFIFOF;

    //During Stream Varibles
    Reg#(DataBytePtr) rmBytePtrReg     <- mkReg(0);
    Reg#(DataBitPtr)  rmBitPtrReg      <- mkReg(0);
    Reg#(DataBytePtr) rsBytePtrReg     <- mkReg(0);
    Reg#(DataBitPtr)  rsBitPtrReg      <- mkReg(0);
    Reg#(Bool)        isDetectedReg    <- mkReg(False);
    Reg#(DataStream)  remainStreamReg  <- mkReg(getEmptyStream);
    Reg#(Bool)        hasLastRemainReg <- mkReg(False);

    rule shape;
        if (hasLastRemainReg) begin
            outFifo.enq(remainStreamReg);
            isDetectedReg <= False;
            hasLastRemainReg <= False;
        end
        else begin
            let stream = inFifo.first;
            inFifo.deq;
            Bool isDetect = !stream.isLast && !isByteEnFull(stream.byteEn) && (!isDetectedReg);
            if (isDetect) begin
                let bytePtr = convertByteEn2BytePtr(stream.byteEn);
                DataBitPtr bitPtr = zeroExtend(bytePtr) << valueOf(BYTE_WIDTH_WIDTH);
                rmBytePtrReg <= bytePtr;
                rmBitPtrReg  <= bitPtr;
                rsBytePtrReg <= getMaxBytePtr - bytePtr;
                rsBitPtrReg  <= getMaxBitPtr - bitPtr;
                remainStreamReg <= stream;
                isDetectedReg <= True;
                if (bytePtr == 0) begin
                    $display($time, "ns SIM Warning @ mkStreamReshape: detect bubble, bytePtr:%d, byteEn: %b", bytePtr, stream.byteEn);
                end
            end
            else begin
                if (isDetectedReg) begin
                    let remainStream = DataStream {
                        data    : stream.data >> rsBitPtrReg,
                        byteEn  : stream.byteEn >> rsBytePtrReg,
                        isFirst : stream.isFirst,
                        isLast  : True
                    };
                    remainStreamReg <= remainStream;
                    let isLast = isByteEnZero(remainStream.byteEn) && stream.isLast;
                    let outStream = DataStream {
                        data    : (stream.data << rmBitPtrReg) | remainStreamReg.data,
                        byteEn  : (stream.byteEn << rmBytePtrReg) | remainStreamReg.byteEn,
                        isFirst : remainStreamReg.isFirst,
                        isLast  : isLast
                    };
                    outFifo.enq(outStream);
                    hasLastRemainReg <= !isByteEnZero(remainStream.byteEn) && stream.isLast;
                    isDetectedReg <= isLast ? False : isDetectedReg;
                end
                else begin
                    outFifo.enq(stream);
                end
            end
        end
    endrule

    interface streamFifoIn  = convertFifoToFifoIn(inFifo);
    interface streamFifoOut = convertFifoToFifoOut(outFifo);
endmodule

typedef Bit#(DWORD_BYTES) DWordByteEn;

module mkStreamRemoveFromDW(StreamPipe);
    FIFOF#(DataStream) inFifo  <- mkFIFOF;
    FIFOF#(DataStream) outFifo <- mkFIFOF;

    Reg#(DataStream)  remainStreamReg  <- mkReg(getEmptyStream);
    Reg#(Bool)        hasLastRemainReg <- mkReg(False);
    Reg#(DataBytePtr) removeByteReg    <- mkReg(0);
    Reg#(DataBytePtr) resByteReg       <- mkReg(getMaxBytePtr);


    function Tuple2#(DataBytePtr, DataBytePtr) getRemoveOffset(DWordByteEn dwByteEn);
        case (dwByteEn) matches
            4'b??10: return tuple2(1, getMaxBytePtr - 1);
            4'b?100: return tuple2(2, getMaxBytePtr - 2);
            4'b1000: return tuple2(3, getMaxBytePtr - 3);
            default: return tuple2(0, getMaxBytePtr);
        endcase
    endfunction

    rule removeHeader;
        if (hasLastRemainReg) begin
            outFifo.enq(remainStreamReg);
            hasLastRemainReg <= False;
            remainStreamReg <= getEmptyStream;
        end
        else begin
            let stream = inFifo.first;
            inFifo.deq;
            let removeByte = removeByteReg;
            let resByte = resByteReg;

            if (stream.isFirst) begin
                {removeByte, resByte} = getRemoveOffset(truncate(stream.byteEn));
            end
            DataBitPtr removeBits = zeroExtend(removeByte) << valueOf(BYTE_WIDTH_WIDTH);
            DataBitPtr resBits = zeroExtend(resByte) << valueOf(BYTE_WIDTH_WIDTH);

            let remainStream = DataStream {
                data    : stream.data >> removeBits,
                byteEn  : stream.byteEn >> removeByte,
                isFirst : stream.isFirst,
                isLast  : stream.isLast
            };
            let newStream = DataStream {
                data    : remainStreamReg.data | stream.data << resBits,
                byteEn  : remainStreamReg.byteEn | stream.byteEn << resByte,
                isFirst : remainStreamReg.isFirst,
                isLast  : isByteEnZero(remainStream.byteEn)
            };
            removeByteReg <= removeByte;
            resByteReg <= resByte;
            
            if (stream.isLast && stream.isFirst) begin 
                outFifo.enq(remainStream);
                hasLastRemainReg <= False;
                remainStreamReg <= getEmptyStream;
            end
            else if (stream.isFirst) begin
                remainStreamReg <= remainStream;
            end
            else begin
                outFifo.enq(newStream);
                if (stream.isLast) begin    
                    if(isByteEnZero(remainStream.byteEn)) begin
                        remainStreamReg <= getEmptyStream;
                        hasLastRemainReg <= False;
                    end
                    else begin
                        remainStreamReg <= remainStream;
                        hasLastRemainReg <= True;
                    end
                end
                else begin
                    remainStreamReg <= remainStream;
                end
            end
        end
    endrule

    interface streamFifoIn  = convertFifoToFifoIn(inFifo);
    interface streamFifoOut = convertFifoToFifoOut(outFifo);
endmodule
