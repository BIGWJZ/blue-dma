import FIFOF::*;
import SemiFifo::*;
import LFSR::*;
import Vector::*;

import BdmaPrimUtils::*;
import DmaTypes::*;
import StreamUtils::*;

typedef 0 LOG_DETAILS_EN;

typedef 'hAB PSEUDO_DATA;
typedef 8    PSEUDO_DATA_WIDTH;

typedef 10 TEST_IDEAL_FIFO_DEPTH;

typedef 'h12345678 SEED_1;
typedef 'hABCDEF01 SEED_2;

// TEST HYPER PARAMETERS CASE 1
// typedef 3 MAX_STREAM_SIZE_PTR;
// typedef 10 TEST_NUM;

// TEST HYPER PARAMETERS CASE 2
typedef 16 MAX_STREAM_SIZE_PTR;
typedef 1000 TEST_NUM;

interface RandomStreamSize;
    method ActionValue#(StreamSize) next();
endinterface

function Data getPseudoData();
    Data pseudoData = fromInteger(valueOf(PSEUDO_DATA));
    for (Integer idx = 0; idx < valueOf(TDiv#(DATA_WIDTH, PSEUDO_DATA_WIDTH)); idx = idx + 1) begin
        pseudoData = pseudoData | (pseudoData << idx*valueOf(PSEUDO_DATA_WIDTH));
    end
    return pseudoData;
endfunction

function DataStream generatePsuedoStream (StreamSize size, Bool isFirst, Bool isLast);
    let pseudoData = getPseudoData();
    let offsetPtr = (unpack(zeroExtend(getMaxBytePtr())) - size) << valueOf(BYTE_WIDTH_WIDTH);
    Data streamData = (pseudoData << offsetPtr) >> offsetPtr;
    return DataStream{
        data: streamData,
        byteEn: (1 << size) - 1,
        isFirst: isFirst,
        isLast: isLast
    };
endfunction

function StreamSize getMaxFrameSize (); 
    return fromInteger(valueOf(BYTE_EN_WIDTH));
endfunction

module mkRandomStreamSize(StreamSize seed, StreamSizeBitPtr maxSizeBitPtr, RandomStreamSize ifc);
    LFSR#(Bit#(STREAM_SIZE_WIDTH)) lfsr <- mkLFSR_32 ;
    FIFOF#(StreamSize) outputFifo <- mkFIFOF ;
    Reg#(Bool) isInitReg <- mkReg(False) ;

    rule run if (isInitReg);
        let value = lfsr.value >> (fromInteger(valueOf(STREAM_SIZE_WIDTH)) - maxSizeBitPtr);
        if (value > 0) begin
            outputFifo.enq(unpack(value));
        end
        lfsr.next;
    endrule

    rule init if (!isInitReg);
        isInitReg <= True;
        lfsr.seed(pack(seed));
    endrule

    method ActionValue#(StreamSize) next();
        outputFifo.deq;
        return outputFifo.first;
    endmethod
endmodule

(* doc = "testcase" *) 
module mkStreamSplitTb(Empty);

    StreamSplit dut <- mkStreamSplit;

    RandomStreamSize streamSizeRandomValue <- mkRandomStreamSize(fromInteger(valueOf(SEED_1)), fromInteger(valueOf(MAX_STREAM_SIZE_PTR)));
    RandomStreamSize splitLocationRandomValue <- mkRandomStreamSize(fromInteger(valueOf(SEED_2)), fromInteger(valueOf(MAX_STREAM_SIZE_PTR)-1));
    
    Reg#(UInt#(32)) testCntReg <- mkReg(0);
    Reg#(UInt#(32)) testRoundReg <- mkReg(0);

    FIFOF#(StreamSize) ideaTotalSizeFifo <- mkSizedFIFOF(valueOf(TEST_IDEAL_FIFO_DEPTH));
    FIFOF#(StreamSize) ideaSplitSizeFifo <- mkSizedFIFOF(valueOf(TEST_IDEAL_FIFO_DEPTH));

    Reg#(StreamSize) streamSize2PutReg <- mkReg(0);
    Reg#(StreamSize) totalRecvSizeReg  <- mkReg(0);

    Reg#(Bool) isInitReg               <- mkReg(False);
    Reg#(Bool) hasRecvFirstChunkReg    <- mkReg(False);

    Bool logDetailEn = unpack(fromInteger(valueOf(LOG_DETAILS_EN)));

    rule testInit if (!isInitReg);
        isInitReg <= True;
        $display("INFO: start mkStreamSplitTb!");
    endrule

    rule testInput if (isInitReg && testCntReg < fromInteger(valueOf(TEST_NUM)));
        // First Frame
        if (streamSize2PutReg == 0) begin
            let size <- streamSizeRandomValue.next;
            let splitLocation <- splitLocationRandomValue.next;
            if (splitLocation < size) begin
                let isLast = size <= getMaxFrameSize();
                let firstSize = isLast ? size : getMaxFrameSize();
                let stream = generatePsuedoStream(firstSize, True, isLast);
                dut.splitLocationFifoIn.enq(splitLocation);
                dut.inputStreamFifoIn.enq(stream);
                ideaTotalSizeFifo.enq(size);
                ideaSplitSizeFifo.enq(splitLocation);
                streamSize2PutReg <= size - firstSize;
                if (logDetailEn) begin
                $display("INFO: Add input stream size %d, split at %d", size, splitLocation);
                end
            end
        end
        else begin
            let isLast = streamSize2PutReg <= getMaxFrameSize();
            let size = isLast ? streamSize2PutReg : getMaxFrameSize();
            let stream = generatePsuedoStream(size, False, isLast);
            dut.inputStreamFifoIn.enq(stream);
            streamSize2PutReg <= streamSize2PutReg - size;
        end
    endrule

    rule testOutput if (isInitReg);
        let outStream = dut.outputStreamFifoOut.first;
        dut.outputStreamFifoOut.deq;
        StreamSize totalSize = totalRecvSizeReg + unpack(zeroExtend(convertByteEn2BytePtr(outStream.byteEn)));
        if (outStream.isLast) begin
            if (hasRecvFirstChunkReg) begin
                immAssert(
                    (totalSize == ideaTotalSizeFifo.first),
                    "outStream total length check @ mkStreamSplitTb",
                    $format("Wrong total length, ideaLen=%d, realLen=%d \n", ideaTotalSizeFifo.first, totalSize)
                );
                if (logDetailEn) begin
                $display("INFO: receive total size", totalSize);
                end
                ideaTotalSizeFifo.deq;
                testCntReg <= testCntReg + 1;
                hasRecvFirstChunkReg <= False;
                totalRecvSizeReg <= 0;
            end 
            else begin
                immAssert(
                    (totalSize == ideaSplitSizeFifo.first),
                    "outStream split location check @ mkStreamSplitTb",
                    $format("Wrong split location, ideaLen=%d, realLen=%d \n", ideaSplitSizeFifo.first, totalSize)
                );
                if (logDetailEn) begin
                $display("INFO: receive first chunk at %d, total size %d", ideaSplitSizeFifo.first, ideaTotalSizeFifo.first);
                end
                ideaSplitSizeFifo.deq;
                hasRecvFirstChunkReg <= True;
                totalRecvSizeReg <= totalSize;
            end
        end
        else begin
            totalRecvSizeReg <= totalSize;
        end
    endrule

    rule testFinish;
        if (testCntReg == fromInteger(valueOf(TEST_NUM)-1)) begin
            $display("INFO: end mkStreamSplitTb");
            $finish();
        end
    endrule

endmodule

module mkStreamShiftTb(Empty);
    RandomStreamSize streamSizeRandomValue <- mkRandomStreamSize(fromInteger(valueOf(SEED_1)), fromInteger(valueOf(MAX_STREAM_SIZE_PTR)));
    Vector#(TAdd#(BYTE_EN_WIDTH, 1), FIFOF#(StreamSize)) setSizeFifo <- replicateM(mkSizedFIFOF(10));
    Vector#(TAdd#(BYTE_EN_WIDTH, 1), StreamPipe)        duts        = newVector;
    for (DataBytePtr idx = 0; idx <= getMaxBytePtr; idx = idx + 1) begin
        duts[idx] <- mkStreamShift(idx);
    end
    
    Reg#(Bool)        isInitReg      <- mkReg(False);
    Reg#(UInt#(32))   testCntReg     <- mkReg(0);
    Reg#(UInt#(32))   testRoundReg   <- mkReg(0);
    Reg#(StreamSize)  remainSizeReg  <- mkReg(0);
    Reg#(UInt#(32))   recvNumReg     <- mkReg(0);

    UInt#(32) testCnt = fromInteger(valueOf(TEST_NUM));
    Bool logDetailEn = unpack(fromInteger(valueOf(LOG_DETAILS_EN)));
    
    rule testInit if (!isInitReg);
        isInitReg <= True;
        $display("INFO: Start StreamShift test");
    endrule

    rule testInput if (isInitReg && testCntReg < testCnt);
        if (testRoundReg == 0) begin
            let size <- streamSizeRandomValue.next;
            if (logDetailEn) begin
            $display("INFO: mkStreamShiftTb input stream size ", size);
            end
            testRoundReg <= size / getMaxFrameSize;
            Bool isLast = (size <= getMaxFrameSize);
            let firstSize = isLast ? size : getMaxFrameSize;
            let testStream = generatePsuedoStream(firstSize, True, isLast);
            remainSizeReg <= size - firstSize;
            testCntReg <= testCntReg + 1;
            for (DataBytePtr idx = 0; idx <= getMaxBytePtr; idx = idx + 1) begin
                setSizeFifo[idx].enq(size);
                duts[idx].streamFifoIn.enq(testStream);
            end
        end
        else begin
            Bool isLast = (remainSizeReg <= getMaxFrameSize);
            let size = isLast ? remainSizeReg : getMaxFrameSize;
            remainSizeReg <= remainSizeReg - size;
            let testStream = generatePsuedoStream(size, False, isLast);
            testRoundReg <= testRoundReg - 1;
            if (size > 0) begin
                for (DataBytePtr idx = 0; idx <= getMaxBytePtr; idx = idx + 1) begin
                    duts[idx].streamFifoIn.enq(testStream);
                end
            end
        end
    endrule

    rule testFinish if (isInitReg && testCntReg == testCnt);
        $display("INFO: End StreamShift test!");
        $finish();
    endrule

    for (DataBytePtr shiftOffset = 0; shiftOffset <= getMaxBytePtr; shiftOffset = shiftOffset + 1) begin
        StreamPipe dut = duts[shiftOffset];

        rule testOutput if (isInitReg);
            let shiftStream = dut.streamFifoOut.first;
            dut.streamFifoOut.deq;
            let ideaSize = setSizeFifo[shiftOffset].first;
            let refStream = getEmptyStream;
            if (shiftStream.isFirst) begin
                let firstSize = ideaSize > getMaxFrameSize ? getMaxFrameSize : ideaSize;
                refStream = generatePsuedoStream(firstSize, True, False);
                refStream.byteEn = refStream.byteEn << shiftOffset;
                DataBitPtr dataShiftOffset = zeroExtend(shiftOffset) << valueOf(BYTE_WIDTH_WIDTH);
                refStream.data   = refStream.data   << dataShiftOffset;
            end
            else if (shiftStream.isLast) begin
                let oriLastSize = ideaSize % fromInteger(valueOf(BYTE_EN_WIDTH));
                let lastSize = oriLastSize + unpack(zeroExtend(shiftOffset));
                lastSize = (lastSize > getMaxFrameSize) ? (lastSize - getMaxFrameSize) : lastSize;
                lastSize = (lastSize == 0) ? getMaxFrameSize : lastSize;
                refStream = generatePsuedoStream(lastSize, False, True);
            end
            else begin
                refStream = generatePsuedoStream(getMaxFrameSize, False, False);
            end
            if (shiftStream.isLast) begin
                setSizeFifo[shiftOffset].deq;
                if (shiftOffset == getMaxBytePtr) begin
                    if (logDetailEn) begin
                    $display("INFO: StreamShift test epoch %d end!", ideaSize);
                    end
                end
            end
            immAssert(
                    (refStream.data == shiftStream.data && refStream.byteEn == shiftStream.byteEn),
                    "shift stream check @ mkStreamShiftTb",
                    $format("streamSize:%d, shiftOffset: %d\n", ideaSize, shiftOffset, "shiftStream", fshow(shiftStream), "refStream", fshow(refStream))
                );
        endrule
    end
endmodule
