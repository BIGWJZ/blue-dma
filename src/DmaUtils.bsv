import FIFOF::*;
import GetPut :: *;
import Vector::*;

import SemiFifo::*;
import PcieTypes::*;
import DmaTypes::*;
import PcieAxiStreamTypes::*;
import BdmaPrimUtils::*;
import StreamUtils::*;
import PcieDescriptorTypes::*;

typedef TAdd#(1, TLog#(TDiv#(BUS_BOUNDARY, BYTE_EN_WIDTH))) DATA_BEATS_WIDTH;
typedef Bit#(DATA_BEATS_WIDTH)                              DataBeats;                 

function Tag convertSlotTokenToTag(SlotToken token, DmaPathNo pathIdx);
    Tag tag = zeroExtend(token) | (zeroExtend(pathIdx) << (valueOf(DES_NONEXTENDED_TAG_WIDTH)-1));
    return tag;
endfunction

typedef 4 CHUNK_COMPUTE_LATENCY;
// Split the input DmaRequest Info MRRS aligned chunkReqs
interface ChunkCompute;
    interface FifoIn#(DmaExtendRequest)  dmaRequestFifoIn;
    interface FifoOut#(DmaRequest)       chunkRequestFifoOut;
    interface FifoOut#(DmaReadReqCnt)    reqCntFifoOut;
    interface Put#(Tuple2#(TlpPayloadSize, TlpPayloadSizeWidth)) maxReadReqSize;
endinterface 

module mkChunkComputer (TRXDirection direction, ChunkCompute ifc);

    FIFOF#(DmaExtendRequest)  inputFifo  <- mkFIFOF;
    FIFOF#(DmaRequest)        outputFifo <- mkFIFOF;
    FIFOF#(Tuple2#(DmaExtendRequest, DmaReqLen))  pipeFifo <- mkFIFOF;
    FIFOF#(DmaReadReqCnt)     rdReqCntFifo <- mkFIFOF;

    Reg#(DmaMemAddr) newChunkPtrReg      <- mkReg(0);
    Reg#(DmaReqLen)  totalLenRemainReg   <- mkReg(0);
    Reg#(Bool)       isSplittingReg      <- mkReg(False);

    FIFOF#(Bool)     mrrsFlagFifo        <- mkFIFOF;
    Reg#(DmaReadReqCnt) rdReqCntReg      <- mkReg(0);
    
    Reg#(DmaReqLen)           tlpMaxSizeReg      <- mkReg(fromInteger(valueOf(DEFAULT_TLP_SIZE)));
    Reg#(TlpPayloadSizeWidth) tlpMaxSizeWidthReg <- mkReg(fromInteger(valueOf(DEFAULT_TLP_SIZE_WIDTH)));   

    function Bool has4KBoundary(DmaExtendRequest request);
        let highIdx = request.endAddr >> valueOf(TLog#(BUS_BOUNDARY));
        let lowIdx = request.startAddr >> valueOf(TLog#(BUS_BOUNDARY));
        return (highIdx > lowIdx);
    endfunction

    function Bool hasBoundary(DmaExtendRequest request);
        let highIdx = request.endAddr >> tlpMaxSizeWidthReg;
        let lowIdx = request.startAddr >> tlpMaxSizeWidthReg;
        return (highIdx > lowIdx);
    endfunction

    function DmaReqLen getOffset(DmaExtendRequest request);
        // offset = MPS - startAddr % MPS
        DmaReqLen remainderOfMps = zeroExtend(TlpPayloadSize'(request.startAddr[tlpMaxSizeWidthReg-1:0]));
        DmaReqLen offsetOfMps = tlpMaxSizeReg - remainderOfMps;    
        return offsetOfMps;
    endfunction

    rule getfirstChunkLen;
        let request = inputFifo.first;
        inputFifo.deq;
        let offset = getOffset(request);
        let firstChunkLen = tlpMaxSizeReg;
        if (request.length > tlpMaxSizeReg || has4KBoundary(request)) begin
            firstChunkLen = offset;
        end
        else begin
            firstChunkLen = request.length;
        end
        pipeFifo.enq(tuple2(request, firstChunkLen));
    endrule

    rule execChunkCompute;
        let {request, firstChunkLen} = pipeFifo.first;
        if (isSplittingReg) begin   // !isFirst
            if (totalLenRemainReg <= tlpMaxSizeReg) begin 
                isSplittingReg <= False; 
                outputFifo.enq(DmaRequest {
                    startAddr : newChunkPtrReg,
                    length    : totalLenRemainReg,
                    isWrite   : False
                });
                pipeFifo.deq;
                mrrsFlagFifo.enq(True);  // this mrrs is done
                totalLenRemainReg <= 0;
            end 
            else begin
                isSplittingReg <= True;
                outputFifo.enq(DmaRequest {
                    startAddr : newChunkPtrReg,
                    length    : tlpMaxSizeReg,
                    isWrite   : False
                });
                mrrsFlagFifo.enq(False); // this mrrs not done
                newChunkPtrReg <= newChunkPtrReg + zeroExtend(tlpMaxSizeReg);
                totalLenRemainReg <= totalLenRemainReg - tlpMaxSizeReg;
            end
        end 
        else begin   // isFirst
            let remainderLength = request.length - firstChunkLen;
            Bool isSplittingNextCycle = (remainderLength > 0);
            isSplittingReg <= isSplittingNextCycle;
            outputFifo.enq(DmaRequest {
                startAddr : request.startAddr,
                length    : firstChunkLen,
                isWrite   : False
            }); 
            if (!isSplittingNextCycle) begin 
                pipeFifo.deq; 
            end
            mrrsFlagFifo.enq(!isSplittingNextCycle);  // this mrrs is done
            newChunkPtrReg <= request.startAddr + zeroExtend(firstChunkLen);
            totalLenRemainReg <= remainderLength;
        end
    endrule

    rule getMrrsReq;
        let flag = mrrsFlagFifo.first;
        mrrsFlagFifo.deq;
        if (flag) begin
            rdReqCntFifo.enq(rdReqCntReg + 1);
            rdReqCntReg <= 0;
            // $display($time, "ns SIM INFO @ mkChunkCompute: split new request to %d MRRS reqs", rdReqCntReg + 1);
        end 
        else begin
            rdReqCntReg <= rdReqCntReg + 1;
        end
        
    endrule

    interface  dmaRequestFifoIn    = convertFifoToFifoIn(inputFifo);
    interface  chunkRequestFifoOut = convertFifoToFifoOut(outputFifo);
    interface  reqCntFifoOut       = convertFifoToFifoOut(rdReqCntFifo);

    interface Put maxReadReqSize;
        method Action put (Tuple2#(TlpPayloadSize, TlpPayloadSizeWidth) mrrsCfg);
            tlpMaxSizeReg <= zeroExtend(tpl_1(mrrsCfg));
            tlpMaxSizeWidthReg <= zeroExtend(tpl_2(mrrsCfg));
        endmethod
    endinterface
    
endmodule

// Split the single input DataStream to a list of DataStream chunks
//  - Chunks cannot violate bus boundary requirement
//  - Only the first and the last chunk can be shorter than MaxPayloadSize
//  - Other chunks length must equal to MaxPayloadSize
//  - The module may block the pipeline if one input beat is splited to two beats
interface ChunkSplit;
    interface FifoIn#(DataStream)       dataFifoIn;
    interface FifoIn#(DmaExtendRequest) reqFifoIn;
    interface FifoOut#(Bool)            doneFifoOut;
    interface FifoOut#(DataStream)      chunkDataFifoOut;
    interface FifoOut#(DmaRequest)      chunkReqFifoOut;
    interface Put#(Tuple2#(TlpPayloadSize, TlpPayloadSizeWidth)) maxPayloadSize;
endinterface

module mkChunkSplit(TRXDirection direction, ChunkSplit ifc);
    FIFOF#(DataStream)  dataInFifo       <- mkFIFOF;
    FIFOF#(DataStream)  chunkOutFifo     <- mkFIFOF;
    FIFOF#(DmaRequest)  reqOutFifo       <- mkFIFOF;
    FIFOF#(Bool)        doneFifo         <- mkFIFOF;
    FIFOF#(DmaRequest)  firstReqPipeFifo <- mkSizedFIFOF(valueOf(STREAM_SPLIT_LATENCY));

    FIFOF#(DmaExtendRequest) reqInFifo        <- mkFIFOF;
    FIFOF#(DmaExtendRequest) inputReqPipeFifo <- mkSizedFIFOF(valueOf(STREAM_SPLIT_LATENCY));

    StreamSplit firstChunkSplitor <- mkStreamSplit;

    Reg#(DmaReqLen)           tlpMaxSizeReg      <- mkReg(fromInteger(valueOf(DEFAULT_TLP_SIZE)));
    Reg#(TlpPayloadSizeWidth) tlpMaxSizeWidthReg <- mkReg(fromInteger(valueOf(DEFAULT_TLP_SIZE_WIDTH)));   
    Reg#(DataBeats)           tlpMaxBeatsReg     <- mkReg(fromInteger(valueOf(TDiv#(DEFAULT_TLP_SIZE, BYTE_EN_WIDTH))));

    Reg#(Bool)      isInProcReg  <- mkReg(False);
    Reg#(Bool)      isInSplitReg <- mkReg(False);
    Reg#(DataBeats) beatsReg     <- mkReg(0);

    Reg#(DmaMemAddr) nextStartAddrReg <- mkReg(0);
    Reg#(DmaReqLen)  remainLenReg     <- mkReg(0);

    function Bool has4KBoundary(DmaExtendRequest request);
        let highIdx = request.endAddr >> valueOf(TLog#(BUS_BOUNDARY));
        let lowIdx = request.startAddr >> valueOf(TLog#(BUS_BOUNDARY));
        return (highIdx > lowIdx);
    endfunction

    function Bool hasBoundary(DmaExtendRequest request);
        let highIdx = request.endAddr >> tlpMaxSizeWidthReg;
        let lowIdx = request.startAddr >> tlpMaxSizeWidthReg;
        return (highIdx > lowIdx);
    endfunction

    function DmaReqLen getOffset(DmaExtendRequest request);
        // MPS - startAddr % MPS, MPS means MRRS when the module is set to RX mode
        DmaReqLen remainderOfMps = zeroExtend(TlpPayloadSize'(request.startAddr[tlpMaxSizeWidthReg-1:0]));
        DmaReqLen offsetOfMps = tlpMaxSizeReg - remainderOfMps;    
        return offsetOfMps;
    endfunction

    // Pipeline stage 1, calculate the first chunkLen which may be smaller than MPS
    rule getfirstChunkLen;
        // If is the first beat of a new request, get firstChunkLen and pipe into the splitor
        if (!isInProcReg) begin
            let request = reqInFifo.first;
            reqInFifo.deq;
            let stream = dataInFifo.first;
            dataInFifo.deq;
            let offset = getOffset(request);
            let firstChunkLen = tlpMaxSizeReg;
            if (request.length > tlpMaxSizeReg || has4KBoundary(request)) begin
                firstChunkLen = offset;
            end
            else begin
                firstChunkLen = request.length;
            end
            // $display($time, "ns SIM INFO @ mkChunkSplit: get first chunkLen, offset %d, remainder %d", offset, TlpPayloadSize'(request.startAddr[tlpMaxSizeWidthReg-1:0]));
            firstChunkSplitor.splitLocationFifoIn.enq(unpack(truncate(firstChunkLen)));
            let firstReq = DmaRequest {
                startAddr : request.startAddr,
                length    : firstChunkLen,
                isWrite   : True
            };
            firstReqPipeFifo.enq(firstReq);
            firstChunkSplitor.inputStreamFifoIn.enq(stream);
            inputReqPipeFifo.enq(request);
            isInProcReg <= !stream.isLast;
        end
        // If is the remain beats of the request, continue pipe into the splitor
        else begin
            let stream = dataInFifo.first;
            dataInFifo.deq;
            firstChunkSplitor.inputStreamFifoIn.enq(stream);
            isInProcReg <= !stream.isLast;
        end 
    endrule

    // Pipeline stage 2: use StreamUtils::StreamSplit to split the input datastream to the firstChunk and the remain chunks
    // In StreamUtils::StreamSplit firstChunkSplitor

    // Pipeline stage 3, set isFirst/isLast accroding to MaxPayloadSize, i.e. split the remain chunks
    rule splitToMps;
        let stream = firstChunkSplitor.outputStreamFifoOut.first;
        firstChunkSplitor.outputStreamFifoOut.deq;
        // End of a TLP, reset beatsReg and tag isLast=True
        if (stream.isLast || beatsReg == tlpMaxBeatsReg - 1) begin
            stream.isLast = True;
            beatsReg <= 0;
        end
        else begin
            beatsReg <= beatsReg + 1;
        end
        // Start of a TLP, get Req Infos and tag isFirst=True
        if (beatsReg == 0) begin
            stream.isFirst = True;
            let nextStartAddr = nextStartAddrReg;
            let remainLen = remainLenReg;
            // The first TLP of chunks
            if (firstReqPipeFifo.notEmpty && !isInSplitReg) begin
                let chunkReq = firstReqPipeFifo.first;
                let oriReq = inputReqPipeFifo.first;
                firstReqPipeFifo.deq;
                inputReqPipeFifo.deq;
                if (chunkReq.length == oriReq.length) begin
                    nextStartAddr = 0;
                    remainLen     = 0;
                    doneFifo.enq(True);
                end
                else begin
                    nextStartAddr = oriReq.startAddr + zeroExtend(chunkReq.length);
                    remainLen     = oriReq.length - chunkReq.length;
                end
                reqOutFifo.enq(chunkReq);
            end
            // The following chunks
            else begin  
                let chunkReq = DmaRequest {
                    startAddr: nextStartAddr,
                    length   : tlpMaxSizeReg,
                    isWrite  : True
                };
                if (!isInSplitReg) begin
                    // Do nothing
                end
                else if (remainLen <= tlpMaxSizeReg) begin
                    chunkReq.length = remainLen;
                    reqOutFifo.enq(chunkReq);
                    nextStartAddr = 0;
                    remainLen     = 0;
                    doneFifo.enq(True);
                end
                else begin
                    nextStartAddr = nextStartAddr + zeroExtend(tlpMaxSizeReg);
                    remainLen     = remainLen - tlpMaxSizeReg;
                    reqOutFifo.enq(chunkReq);
                end
            end
            // $display($time, "ns SIM INFO @ mkChunkSplit: output chunkReq.");
            nextStartAddrReg <= nextStartAddr;
            remainLenReg <= remainLen;
            isInSplitReg <= (remainLen != 0);
        end
        chunkOutFifo.enq(stream);
    endrule

    interface dataFifoIn  = convertFifoToFifoIn(dataInFifo);
    interface reqFifoIn   = convertFifoToFifoIn(reqInFifo);
    interface doneFifoOut = convertFifoToFifoOut(doneFifo);

    interface chunkDataFifoOut = convertFifoToFifoOut(chunkOutFifo);
    interface chunkReqFifoOut  = convertFifoToFifoOut(reqOutFifo);

    interface Put maxPayloadSize;
        method Action put (Tuple2#(TlpPayloadSize, TlpPayloadSizeWidth) mpsCfg);
            tlpMaxSizeReg <= zeroExtend(tpl_1(mpsCfg));
            tlpMaxSizeWidthReg <= tpl_2(mpsCfg);
            // BeatsNum = (MaxPayloadSize + DescriptorSize) / BytesPerBeat
            tlpMaxBeatsReg <= truncate(tpl_1(mpsCfg) >> valueOf(TLog#(BYTE_EN_WIDTH)));
        endmethod
    endinterface
endmodule

// Generate RequesterRequest descriptor 
interface RqDescriptorGenerator;
    interface FifoIn#(DmaExtendRequest) exReqFifoIn;
    interface FifoOut#(DataStream)      descFifoOut;
    interface FifoOut#(SideBandByteEn)  byteEnFifoOut;
endinterface

module mkRqDescriptorGenerator#(Bool isWrite)(RqDescriptorGenerator);
    FIFOF#(DmaExtendRequest) exReqInFifo <- mkFIFOF;
    FIFOF#(DataStream)       descOutFifo <- mkFIFOF;
    FIFOF#(SideBandByteEn)   byteEnOutFifo <- mkFIFOF;

    rule genRqDesc;
        let exReq = exReqInFifo.first;
        exReqInFifo.deq;
        let endOffset = byteModDWord(exReq.endAddr); 
        DwordCount dwCnt = truncate((exReq.endAddr >> valueOf(BYTE_DWORD_SHIFT_WIDTH)) - (exReq.startAddr >> valueOf(BYTE_DWORD_SHIFT_WIDTH))) + 1;
        dwCnt = (exReq.length == 0) ? 1 : dwCnt;
        DataBytePtr bytePtr = fromInteger(valueOf(TDiv#(DES_RQ_DESCRIPTOR_WIDTH, BYTE_WIDTH)));
        let descriptor  = PcieRequesterRequestDescriptor {
                forceECRC       : False,
                attributes      : fromInteger(valueof(ATTR_NO_SNOOP)),
                trafficClass    : 0,
                requesterIdEn   : False,
                completerId     : 0,
                tag             : exReq.tag,
                requesterId     : 0,
                isPoisoned      : False,
                reqType         : isWrite ? fromInteger(valueOf(MEM_WRITE_REQ)) : fromInteger(valueOf(MEM_READ_REQ)),
                dwordCnt        : dwCnt,
                address         : truncate(exReq.startAddr >> valueOf(BYTE_DWORD_SHIFT_WIDTH)),
                addrType        : fromInteger(valueOf(UNTRANSLATED_ADDR))
            };
        let stream = DataStream {
            data    : zeroExtend(pack(descriptor)),
            byteEn  : convertBytePtr2ByteEn(bytePtr),
            isFirst : True,
            isLast  : True
        };
        descOutFifo.enq(stream);
        let startAddrOffset = byteModDWord(exReq.startAddr);
        let endAddrOffset = byteModDWord(exReq.endAddr);
        let firstByteEn = convertDWordOffset2FirstByteEn(startAddrOffset);
        let lastByteEn = convertDWordOffset2LastByteEn(endAddrOffset);
    // if startAddr and endAddr are in the same DWord
        if ((exReq.startAddr >> valueOf(TLog#(DWORD_BYTES))) == (exReq.endAddr >> valueOf(TLog#(DWORD_BYTES)))) begin
            firstByteEn = firstByteEn & lastByteEn;
            lastByteEn = 0;
        end
        byteEnOutFifo.enq(tuple2(firstByteEn, lastByteEn));
        // $display($time, "ns SIM INFO @ mkRqDescriptorGenerator: generate desc, tag %d, dwcnt %d, start:%d, end:%d, byteCnt:%d ", exReq.tag, dwCnt, exReq.startAddr, exReq.endAddr, exReq.length);
    endrule

    interface exReqFifoIn = convertFifoToFifoIn(exReqInFifo);
    interface descFifoOut = convertFifoToFifoOut(descOutFifo);
    interface byteEnFifoOut = convertFifoToFifoOut(byteEnOutFifo);
endmodule

