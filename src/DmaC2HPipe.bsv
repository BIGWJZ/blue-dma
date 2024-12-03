import FIFOF::*;
import GetPut::*;
import Vector::*;
import Connectable::*;
import ClientServer::*;

import SemiFifo::*;
import BdmaPrimUtils::*;
import StreamUtils::*;
import PcieTypes::*;
import DmaTypes::*;
import PcieAxiStreamTypes::*;
import PcieDescriptorTypes::*;
import DmaUtils::*;
import CompletionFifo::*;

// Wrapper between original dma pipe and blue-rdma style interface
interface BdmaC2HPipe;
    // User Logic Ifc
    interface Server#(BdmaUserC2hWrReq, BdmaUserC2hWrResp) writeSrv;
    interface Server#(BdmaUserC2hRdReq, BdmaUserC2hRdResp) readSrv;

    // Pcie Adapter Ifc
    interface FifoOut#(DataStream)     tlpDataFifoOut;
    interface FifoOut#(SideBandByteEn) tlpSideBandFifoOut;
    interface FifoIn#(StraddleStream)  tlpDataFifoIn;
    // TODO: CSR Ifc
    interface Put#(TlpSizeCfg)   tlpSizeCfg;
    // interface Client#(DmaCsrValue, DmaCsrValue) statusReg;
endinterface

module mkBdmaC2HPipe#(DmaPathNo pathIdx)(BdmaC2HPipe);
    C2HReadCore  readCore  <- mkC2HReadCore(pathIdx);
    C2HWriteCore writeCore <- mkC2HWriteCore(pathIdx);

    Reg#(Bool) isInitDoneReg <- mkReg(False);
    Reg#(Bool) isInWriteCoreOutputReg <- mkReg(False);

    FIFOF#(BdmaUserC2hWrReq)  wrReqInFifo   <- mkFIFOF;
    FIFOF#(BdmaUserC2hWrResp) wrRespOutFifo <- mkFIFOF;
    FIFOF#(BdmaUserC2hRdReq)  rdReqInFifo   <- mkFIFOF;
    FIFOF#(BdmaUserC2hRdResp) rdRespOutFifo <- mkFIFOF;

    FIFOF#(DataStream)     tlpOutFifo      <- mkFIFOF;
    FIFOF#(SideBandByteEn) tlpSideBandFifo <- mkFIFOF;

    rule forwardWrReq if (isInitDoneReg);
        let req = wrReqInFifo.first;
        wrReqInFifo.deq;
        writeCore.dataFifoIn.enq(req.dataStream);
        writeCore.wrReqFifoIn.enq(DmaRequest {
            startAddr: req.addr,
            length   : req.len,
            isWrite  : True
        });
        $display($time, "ns SIM INFO @ mkBdmaC2HPipe%d: recv new request, startAddr:%d length:%d isWrite:%b",
                pathIdx, req.addr, req.len, 1);
    endrule

    rule forwardWrResp if (isInitDoneReg);
        let rv = writeCore.doneFifoOut.first;
        writeCore.doneFifoOut.deq;
        wrRespOutFifo.enq(BdmaUserC2hWrResp{ });
    endrule

    rule forwardRdReq if (isInitDoneReg);
        let req = rdReqInFifo.first;
        rdReqInFifo.deq;
        readCore.rdReqFifoIn.enq(DmaRequest {
            startAddr: req.addr,
            length   : req.len,
            isWrite  : False
        });
        $display($time, "ns SIM INFO @ mkBdmaC2HPipe%d: recv new request, startAddr:%d length:%d isWrite:%b",
                pathIdx, req.addr, req.len, 0);
    endrule

    rule forwardRdResp if (isInitDoneReg);
        let stream = readCore.dataFifoOut.first;
        readCore.dataFifoOut.deq;
        rdRespOutFifo.enq(BdmaUserC2hRdResp{
            dataStream: stream
        });
    endrule

    rule muxTlpOut;
        if (isInWriteCoreOutputReg) begin
            let tlpStream = writeCore.tlpFifoOut.first;
            tlpOutFifo.enq(tlpStream);
            writeCore.tlpFifoOut.deq;
            isInWriteCoreOutputReg <= !tlpStream.isLast;
        end
        else begin
            if (readCore.tlpFifoOut.notEmpty) begin
                tlpOutFifo.enq(readCore.tlpFifoOut.first);
                tlpSideBandFifo.enq(readCore.tlpSideBandFifoOut.first);
                readCore.tlpFifoOut.deq;
                readCore.tlpSideBandFifoOut.deq;
            end
            else begin
                tlpOutFifo.enq(writeCore.tlpFifoOut.first);
                tlpSideBandFifo.enq(writeCore.tlpSideBandFifoOut.first);
                writeCore.tlpFifoOut.deq;
                writeCore.tlpSideBandFifoOut.deq;
                isInWriteCoreOutputReg <= !writeCore.tlpFifoOut.first.isLast;
            end
        end
    endrule

    // User Ifc
    interface readSrv  = toGPServer(rdReqInFifo, rdRespOutFifo);
    interface writeSrv = toGPServer(wrReqInFifo, wrRespOutFifo);
    
    // Pcie Adapter Ifc
    interface tlpDataFifoOut      = convertFifoToFifoOut(tlpOutFifo);
    interface tlpSideBandFifoOut  = convertFifoToFifoOut(tlpSideBandFifo);
    interface tlpDataFifoIn       = readCore.tlpFifoIn;
    // TODO: CSR Ifc
    interface Put tlpSizeCfg;
        method Action put(sizeCfg);
            writeCore.maxPayloadSize.put(tuple2(sizeCfg.mps, sizeCfg.mpsWidth));
            readCore.maxReadReqSize.put(tuple2(sizeCfg.mrrs, sizeCfg.mrrsWidth));
            isInitDoneReg <= True;
        endmethod
    endinterface

endmodule

// TODO : change the PCIe Adapter Ifc to TlpData and TlpHeader, 
//        move the module which convert TlpHeader to IP descriptor from dma to adapter
interface DmaC2HPipe;
    // User Logic Ifc
    interface FifoIn#(DataStream)  wrDataFifoIn;
    interface FifoIn#(DmaRequest)  reqFifoIn;
    interface FifoOut#(DataStream) rdDataFifoOut;
    interface FifoOut#(Bool)       doneFifoOut;
    // Pcie Adapter Ifc
    interface FifoOut#(DataStream)     tlpDataFifoOut;
    interface FifoOut#(SideBandByteEn) tlpSideBandFifoOut;
    interface FifoIn#(StraddleStream)  tlpDataFifoIn;
    // TODO: CSR Ifc
    interface Put#(TlpSizeCfg)   tlpSizeCfg;
    // interface Client#(DmaCsrValue, DmaCsrValue) statusReg;
endinterface

// Single Path module
(* synthesize *)
module mkDmaC2HPipe#(DmaPathNo pathIdx)(DmaC2HPipe);
    C2HReadCore  readCore  <- mkC2HReadCore(pathIdx);
    C2HWriteCore writeCore <- mkC2HWriteCore(pathIdx);

    Reg#(Bool) isInitDoneReg <- mkReg(False);
    Reg#(Bool) isInWriteCoreOutputReg <- mkReg(False);

    FIFOF#(DataStream) dataInFifo   <- mkFIFOF;
    FIFOF#(DmaRequest) reqInFifo    <- mkFIFOF;
    FIFOF#(DataStream) tlpOutFifo   <- mkFIFOF;
    FIFOF#(SideBandByteEn) tlpSideBandFifo <- mkFIFOF;

    mkConnection(dataInFifo, writeCore.dataFifoIn);

    rule reqDeMux if (isInitDoneReg);
        let req = reqInFifo.first;
        reqInFifo.deq;
        if (req.isWrite) begin
            writeCore.wrReqFifoIn.enq(req);
        end
        else begin
            readCore.rdReqFifoIn.enq(req);
        end
        $display($time, "ns SIM INFO @ mkDmaC2HPipe%d: recv new request, startAddr:%d length:%d isWrite:%b",
                pathIdx, req.startAddr, req.length,  pack(req.isWrite));
    endrule

    // rule tlpOutMux;
    //     if (readCore.tlpFifoOut.notEmpty) begin
    //         tlpOutFifo.enq(readCore.tlpFifoOut.first);
    //         tlpSideBandFifo.enq(readCore.tlpSideBandFifoOut.first);
    //         readCore.tlpSideBandFifoOut.deq;
    //         readCore.tlpFifoOut.deq;
    //     end
    //     else begin
    //         if (writeCore.tlpSideBandFifoOut.notEmpty) begin
    //             tlpSideBandFifo.enq(writeCore.tlpSideBandFifoOut.first);
    //             writeCore.tlpSideBandFifoOut.deq;
    //         end
    //         tlpOutFifo.enq(writeCore.tlpFifoOut.first);
    //         writeCore.tlpFifoOut.deq;
    //     end
    // endrule

    rule muxTlpOut;
        if (isInWriteCoreOutputReg) begin
            let tlpStream = writeCore.tlpFifoOut.first;
            tlpOutFifo.enq(tlpStream);
            writeCore.tlpFifoOut.deq;
            isInWriteCoreOutputReg <= !tlpStream.isLast;
        end
        else begin
            if (readCore.tlpFifoOut.notEmpty) begin
                tlpOutFifo.enq(readCore.tlpFifoOut.first);
                tlpSideBandFifo.enq(readCore.tlpSideBandFifoOut.first);
                readCore.tlpFifoOut.deq;
                readCore.tlpSideBandFifoOut.deq;
            end
            else begin
                tlpOutFifo.enq(writeCore.tlpFifoOut.first);
                tlpSideBandFifo.enq(writeCore.tlpSideBandFifoOut.first);
                writeCore.tlpFifoOut.deq;
                writeCore.tlpSideBandFifoOut.deq;
                isInWriteCoreOutputReg <= !writeCore.tlpFifoOut.first.isLast;
            end
        end
    endrule

    // User Logic Ifc
    interface wrDataFifoIn  = convertFifoToFifoIn(dataInFifo);
    interface reqFifoIn     = convertFifoToFifoIn(reqInFifo);
    interface rdDataFifoOut = readCore.dataFifoOut;
    interface doneFifoOut   = writeCore.doneFifoOut;
    // Pcie Adapter Ifc
    interface tlpDataFifoOut      = convertFifoToFifoOut(tlpOutFifo);
    interface tlpSideBandFifoOut  = convertFifoToFifoOut(tlpSideBandFifo);
    interface tlpDataFifoIn       = readCore.tlpFifoIn;
    // TODO: CSR Ifc
    interface Put tlpSizeCfg;
        method Action put(sizeCfg);
            writeCore.maxPayloadSize.put(tuple2(sizeCfg.mps, sizeCfg.mpsWidth));
            readCore.maxReadReqSize.put(tuple2(sizeCfg.mrrs, sizeCfg.mrrsWidth));
            isInitDoneReg <= True;
        endmethod
    endinterface
endmodule

interface C2HReadCore;
    // User Logic Ifc
    interface FifoOut#(DataStream)     dataFifoOut;
    interface FifoIn#(DmaRequest)      rdReqFifoIn;
    // PCIe IP Ifc, connect to Requester Adapter
    interface FifoIn#(StraddleStream)  tlpFifoIn;
    interface FifoOut#(DataStream)     tlpFifoOut;
    interface FifoOut#(SideBandByteEn) tlpSideBandFifoOut;

    interface Put#(Tuple2#(TlpPayloadSize, TlpPayloadSizeWidth)) maxReadReqSize;
endinterface

// Total Latency(Tlp Output): 1 + 2 + 1 + 1 = 5
// Total Latency(Tlp Input) : 1\2 + 2 + n + 2 + 1 = 5/6 + n (depends on the order)
module mkC2HReadCore#(DmaPathNo pathIdx)(C2HReadCore);
    FIFOF#(StraddleStream) tlpInFifo      <- mkFIFOF;
    FIFOF#(DmaRequest)     reqInFifo      <- mkFIFOF;
    FIFOF#(DataStream)     tlpOutFifo     <- mkFIFOF;
    FIFOF#(SideBandByteEn) tlpByteEnFifo  <- mkFIFOF;

    FIFOF#(SlotToken)      tagFifo         <- mkSizedFIFOF(valueOf(TAdd#(1, STREAM_HEADER_REMOVE_LATENCY)));      
    FIFOF#(Bool)           completedFifo   <- mkSizedFIFOF(valueOf(TAdd#(1, STREAM_HEADER_REMOVE_LATENCY)));   
    FIFOF#(DmaReadReqCnt)  inflightFifo    <- mkSizedFIFOF(valueOf(SLOT_PER_PATH));


    StreamPipe     descRemove     <- mkStreamHeaderRemove(fromInteger(valueOf(TDiv#(DES_RC_DESCRIPTOR_WIDTH, BYTE_WIDTH)))); 
    StreamPipe     dwRemove       <- mkStreamRemoveFromDW;
    StreamPipe     reshapeStrad   <- mkStreamReshape;
    StreamPipe     reshapeRcb     <- mkStreamReshape;
    StreamPipe     reshapeMrrs    <- mkStreamReshape;
    ChunkCompute   chunkSplitor   <- mkChunkComputer(DMA_RX);
    CompletionFifo#(SLOT_PER_PATH, DataStream)  cBuffer <- mkCompletionFifo(valueOf(MAX_STREAM_NUM_PER_COMPLETION));
    RqDescriptorGenerator rqDescGenerator <- mkRqDescriptorGenerator(False);
    
    Reg#(Bool) hasReadOnceReg   <- mkReg(False);
    Reg#(Bool) isStreamValidReg <- mkReg(True);
    Reg#(DmaReadReqCnt)          rcvReqCntReg  <- mkReg(1);
    Vector#(SLOT_PER_PATH, Reg#(Bool)) chunkFlagRegs <- replicateM(mkReg(False));

    mkConnection(reshapeStrad.streamFifoOut, descRemove.streamFifoIn);
    mkConnection(descRemove.streamFifoOut, dwRemove.streamFifoIn);
    mkConnection(chunkSplitor.reqCntFifoOut, inflightFifo);

    // Pipeline stage 1: convert StraddleStream to DataStream, may cost 2 cycle for one StraddleStream
    rule convertStraddleToDataStream;
        let sdStream = tlpInFifo.first;
        let stream   = getEmptyStream;
        SlotToken tag = 0;
        Bool isCompleted = False;
        if (sdStream.isDoubleFrame) begin
            PcieTlpCtlIsSopPtr isSopPtr = 0;
            if (hasReadOnceReg) begin
                tlpInFifo.deq;
                hasReadOnceReg <= False;
                isSopPtr = 1;
            end
            else begin
                hasReadOnceReg <= True;
            end
            stream = DataStream {
                data    : getStraddleData(isSopPtr, sdStream.data),
                byteEn  : getStraddleByteEn(isSopPtr, sdStream.byteEn),
                isFirst : sdStream.isFirst[isSopPtr],
                isLast  : sdStream.isLast[isSopPtr]
            };
            tag = sdStream.tag[isSopPtr];
            isCompleted = sdStream.isCompleted[isSopPtr];
        end
        else begin
            tlpInFifo.deq;
            hasReadOnceReg <= False;
            stream = DataStream {
                data    : sdStream.data,
                byteEn  : sdStream.byteEn,
                isFirst : sdStream.isFirst[0],
                isLast  : sdStream.isLast[0]
            };
            tag = sdStream.tag[0];
            isCompleted = sdStream.isCompleted[0]; 
        end
        stream.byteEn = stream.byteEn;
        Bool isStreamValid = isStreamValidReg;
        if (stream.isFirst) begin
            PcieRequesterCompleteDescriptor desc = unpack(truncate(stream.data));
            isStreamValid = (desc.errorcode == 0);
        end 
        if (isStreamValid) begin
            reshapeStrad.streamFifoIn.enq(stream);
            if (stream.isFirst) begin
                tagFifo.enq(tag);
                completedFifo.enq(isCompleted);
            end
        end
        isStreamValidReg <= isStreamValid;
        // $display("parse from straddle, tag: %d, cmpl status: %d", tag, pack(isCompleted), fshow(stream));
    endrule

    // Pipeline stage 2: remove the descriptor in the head of each TLP

    // Pipeline stage 3: Buffer the received DataStreams and reorder them
    rule reorderStream;
        let stream = dwRemove.streamFifoOut.first;
        let byteInStream = convertByteEn2BytePtr(stream.byteEn);
        let isCompleted = completedFifo.first;
        let tag = tagFifo.first;
        let rcvdFlag = True;
        dwRemove.streamFifoOut.deq;
        // $display($time, "ns SIM INFO @ mkDmaC2HReadCore%d: from dwRemove to cBuf, tag: %d, cmpl: %d", pathIdx, tag, pack(isCompleted), fshow(stream));
        if (stream.isLast) begin
            completedFifo.deq;
            tagFifo.deq;
        end
        stream.isLast = isCompleted && stream.isLast;   //Re-define the stream boundary
        stream.isFirst = stream.isFirst && (!chunkFlagRegs[tag]);
        cBuffer.append.enq(tuple2(tag, stream));
        if (stream.isLast) begin
            cBuffer.complete.put(tag);
            // $display($time, "ns SIM INFO @ mkDmaC2HReadCore%d: a chunk is completed in cBuffer, tag: %d", pathIdx, tag);
            rcvdFlag = False;
        end
        chunkFlagRegs[tag] <= rcvdFlag;
    endrule

    // Pipeline stage 4: there may be a bubble between the first and last DataStream of cBUffer drain output
    //  Reshape the DataStream from RCB chunks to MRRS chunks
    rule reshapeRCB;
        let stream = cBuffer.drain.first;
        cBuffer.drain.deq;
        reshapeRcb.streamFifoIn.enq(stream);
        // $display("cbuf output", fshow(stream));
    endrule

    // Pipeline stage 4: there may be bubbles in the first and last DataStream of a request because of MRRS split
    //  Reshape the DataStream from MRRS chunks to a whole DataStream 
    rule reshapeMRRS;
        let stream = reshapeRcb.streamFifoOut.first;
        reshapeRcb.streamFifoOut.deq;
        if (stream.isLast) begin
            let rcvReqCnt = rcvReqCntReg;
            // $display("DEBUG: get isLast from reshapeRcb, fifo.first:%d, rcvReqCntReg: %d", inflightFifo.first, rcvReqCntReg);
            if (inflightFifo.first == rcvReqCnt) begin
                rcvReqCnt = 1;
                inflightFifo.deq;
            end 
            else begin
                rcvReqCnt = rcvReqCnt + 1;
                stream.isLast = False;
            end
            rcvReqCntReg <= rcvReqCnt;
        end
        stream.isFirst = stream.isFirst && (rcvReqCntReg == 1);
        reshapeMrrs.streamFifoIn.enq(stream);
    endrule

    // Pipeline stage 1: split to req to MRRS chunks
    rule reqSplit;
        let req = reqInFifo.first;
        reqInFifo.deq;
        let exReq = DmaExtendRequest {
            startAddr : req.startAddr,
            endAddr   : req.startAddr + zeroExtend(req.length - 1),
            length    : req.length,
            tag       : 0
        };
        chunkSplitor.dmaRequestFifoIn.enq(exReq);
    endrule

    // Pipeline stage 2: generate read descriptor
    rule cqDescGen;
        let req = chunkSplitor.chunkRequestFifoOut.first;
        chunkSplitor.chunkRequestFifoOut.deq;
        let token <- cBuffer.reserve.get;
        let exReq = DmaExtendRequest {
                startAddr:  req.startAddr,
                endAddr  :  req.startAddr + zeroExtend(req.length - 1),
                length   :  req.length,
                tag      :  convertSlotTokenToTag(token, pathIdx)
            };
        rqDescGenerator.exReqFifoIn.enq(exReq);
        // $display($time, "ns SIM INFO @ mkDmaC2HReadCore%d: tx a new read chunk, tag:%d, addr:%d, length:%d", pathIdx, exReq.tag, req.startAddr, req.length);
    endrule

    // Pipeline stage 3: generate Tlp to PCIe Adapter
    rule tlpGen;
        let stream = rqDescGenerator.descFifoOut.first;
        let sideBandByteEn = rqDescGenerator.byteEnFifoOut.first;
        rqDescGenerator.descFifoOut.deq;
        rqDescGenerator.byteEnFifoOut.deq;
        stream.isFirst = True;
        stream.isLast  = True;
        tlpOutFifo.enq(stream);
        tlpByteEnFifo.enq(sideBandByteEn);
        // $display($time, "ns SIM INFO @ mkDmaC2HReadCore%d: output new tlp, BE:%h/%h", pathIdx, tpl_1(sideBandByteEn), tpl_2(sideBandByteEn));
    endrule

    // User Logic Ifc
    interface rdReqFifoIn = convertFifoToFifoIn(reqInFifo);
    interface dataFifoOut = reshapeMrrs.streamFifoOut;
    // PCIe IP Ifc
    interface tlpFifoIn   = convertFifoToFifoIn(tlpInFifo);
    interface tlpFifoOut  = convertFifoToFifoOut(tlpOutFifo);
    interface tlpSideBandFifoOut = convertFifoToFifoOut(tlpByteEnFifo);
    // Cfg Ifc
    interface Put maxReadReqSize;
        method Action put(Tuple2#(TlpPayloadSize, TlpPayloadSizeWidth) mrrsCfg);
            chunkSplitor.maxReadReqSize.put(mrrsCfg);
        endmethod
    endinterface
endmodule

// Core path of a single stream, from (DataStream, DmaRequest) ==> (DataStream, SideBandByteEn)
// split to chunks, align to DWord and add descriptor at the first
interface C2HWriteCore;
    // User Logic Ifc
    interface FifoIn#(DataStream)      dataFifoIn;
    interface FifoIn#(DmaRequest)      wrReqFifoIn;
    interface FifoOut#(Bool)           doneFifoOut;
    // PCIe IP Ifc
    interface FifoOut#(DataStream)     tlpFifoOut;
    interface FifoOut#(SideBandByteEn) tlpSideBandFifoOut;
    
    interface Put#(Tuple2#(TlpPayloadSize, TlpPayloadSizeWidth)) maxPayloadSize;
endinterface

// Total Latency: 1 + 3 + 2 + 1 = 7
module mkC2HWriteCore#(DmaPathNo pathIdx)(C2HWriteCore);
    FIFOF#(DataStream)     dataInFifo  <- mkFIFOF;
    FIFOF#(DmaRequest)     wrReqInFifo <- mkFIFOF;
    FIFOF#(DataStream)     dataOutFifo <- mkFIFOF;
    FIFOF#(SideBandByteEn) byteEnOutFifo <- mkFIFOF;

    Reg#(SlotToken)  tagReg <- mkReg(0);

    ChunkSplit chunkSplit <- mkChunkSplit(DMA_TX);
    StreamShiftAlignToDw streamAlign <- mkStreamShiftAlignToDw(fromInteger(valueOf(TDiv#(DES_RQ_DESCRIPTOR_WIDTH, BYTE_WIDTH))));
    RqDescriptorGenerator rqDescGenerator <- mkRqDescriptorGenerator(True);

    // Pipeline stage 1: split the whole write request to chunks, latency = 3
    rule splitToChunks;
        let wrStream = dataInFifo.first;
        // if (wrStream.isLast || wrStream.isFirst) begin $display($time, "ns SIM INFO @ mkC2HWriteCore: ", fshow(wrStream)); end
        if (wrStream.isFirst && wrReqInFifo.notEmpty) begin
            wrReqInFifo.deq;
            let wrReq = wrReqInFifo.first;
            let exReq = DmaExtendRequest {
                startAddr : wrReq.startAddr,
                endAddr   : wrReq.startAddr + zeroExtend(wrReq.length - 1),
                length    : wrReq.length,
                tag       : 0
            };
            chunkSplit.reqFifoIn.enq(exReq);
            dataInFifo.deq;
            chunkSplit.dataFifoIn.enq(wrStream);
        end
        else if (!wrStream.isFirst) begin
            dataInFifo.deq;
            chunkSplit.dataFifoIn.enq(wrStream);
        end
    endrule

    // Pipeline stage 2: shift the datastream for descriptor adding and dw alignment
    rule shiftToAlignment;
        if (chunkSplit.chunkReqFifoOut.notEmpty) begin
            let chunkReq = chunkSplit.chunkReqFifoOut.first;
            chunkSplit.chunkReqFifoOut.deq;
            let exReq = DmaExtendRequest {
                startAddr:  chunkReq.startAddr,
                endAddr  :  chunkReq.startAddr + zeroExtend(chunkReq.length - 1),
                length   :  chunkReq.length,
                tag      :  convertSlotTokenToTag(tagReg, pathIdx)
            };
            tagReg <= tagReg + 1;
            let startAddrOffset = byteModDWord(exReq.startAddr);
            streamAlign.setAlignMode(unpack(startAddrOffset));
            rqDescGenerator.exReqFifoIn.enq(exReq);
            $display($time, "ns SIM INFO @ mkDmaC2HWriteCore%d: tx a new write chunk, tag:%d, addr:%d, length:%d", pathIdx, convertSlotTokenToTag(tagReg, pathIdx), chunkReq.startAddr, chunkReq.length);
        end
        if (chunkSplit.chunkDataFifoOut.notEmpty) begin
            let chunkDataStream = chunkSplit.chunkDataFifoOut.first;
            chunkSplit.chunkDataFifoOut.deq;
            streamAlign.dataFifoIn.enq(chunkDataStream);
            // if (chunkDataStream.isLast && chunkDataStream.isFirst) begin
            //     $display($time, "ns SIM INFO @ mkDmaC2HWriteCore%d: tx write chunk end  , tag:%d", pathIdx, convertSlotTokenToTag(tagReg, pathIdx));
            // end
            // else if (chunkDataStream.isLast) begin
            //     $display($time, "ns SIM INFO @ mkDmaC2HWriteCore%d: tx write chunk end  , tag:%d", pathIdx, convertSlotTokenToTag(tagReg-1, pathIdx));
            // end
        end
    endrule

    // Pipeline stage 3: Add descriptor and add to the axis convert module
    rule addDescriptorToAxis;
        let stream = streamAlign.dataFifoOut.first;
        streamAlign.dataFifoOut.deq;
        if (stream.isFirst) begin
            let descStream = rqDescGenerator.descFifoOut.first;
            let sideBandByteEn = rqDescGenerator.byteEnFifoOut.first;
            rqDescGenerator.descFifoOut.deq;
            rqDescGenerator.byteEnFifoOut.deq;
            stream.data = stream.data | descStream.data;
            stream.byteEn = stream.byteEn | descStream.byteEn;
            byteEnOutFifo.enq(sideBandByteEn);
            // $display($time, "ns SIM INFO @ mkDmaC2HWriteCore%d: tx a new tlp, BE:%b/%b", pathIdx, tpl_1(sideBandByteEn), tpl_2(sideBandByteEn));
        end
        dataOutFifo.enq(stream);
        // $display($time, "ns SIM INFO @ mkDmaC2HWriteCore%d: tlp stream", pathIdx, fshow(stream));
    endrule

    // User Logic Ifc
    interface dataFifoIn         = convertFifoToFifoIn(dataInFifo);
    interface wrReqFifoIn        = convertFifoToFifoIn(wrReqInFifo);
    interface doneFifoOut        = chunkSplit.doneFifoOut;
    // PCIe Adapter Ifc
    interface tlpFifoOut         = convertFifoToFifoOut(dataOutFifo);
    interface tlpSideBandFifoOut = convertFifoToFifoOut(byteEnOutFifo);
    // Cfg Ifc
    interface Put maxPayloadSize;
        method Action put(Tuple2#(TlpPayloadSize, TlpPayloadSizeWidth) mpsCfg);
            chunkSplit.maxPayloadSize.put(mpsCfg);
        endmethod
    endinterface
endmodule
