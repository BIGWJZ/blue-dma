import GetPut::*;
import Randomizable::*;
import Vector::*;
import Connectable::*;

import SemiFifo::*;
import PcieAxiStreamTypes::*;
import DmaTypes::*;
import BdmaPrimUtils::*;
import PcieTypes::*;
import PcieDescriptorTypes::*;
import StreamUtils::*;
import PcieAdapter::*;
import TestStreamUtils::*;
import DmaUtils::*;
import DmaC2HPipe::*;


typedef 100000 CHUNK_PER_EPOCH_TEST_NUM;
typedef 64'hFFFFFFFFFFFFFFFF MAX_ADDRESS;
typedef 16'hFFFF MAX_TEST_LENGTH;
typedef 2'b00 DEFAULT_TLP_SIZE_SETTING;
typedef 4   CHUNK_TX_TEST_SETTING_NUM;
typedef 6   CHUNK_RX_TEST_SETTING_NUM;

module mkChunkComputerTb(Empty);

    ChunkCompute dut <- mkChunkComputer(DMA_TX);

    Reg#(Bool)       isInitReg   <- mkReg(False);
    Reg#(UInt#(32))  testCntReg  <- mkReg(0); 
    Reg#(UInt#(32))  epochCntReg <- mkReg(0); 

    Reg#(DmaReqLen) lenRemainReg <- mkReg(0);

    Randomize#(DmaMemAddr) startAddrRandomVal <- mkConstrainedRandomizer(0, fromInteger(valueOf(MAX_ADDRESS)-1));
    Randomize#(DmaReqLen) lengthRandomVal    <- mkConstrainedRandomizer(1, fromInteger(valueOf(MAX_TEST_LENGTH)));

    function Bool hasBoundary(DmaRequest request);
        let highIdx = (request.startAddr + zeroExtend(request.length) - 1) >> valueOf(BUS_BOUNDARY_WIDTH);
        let lowIdx = request.startAddr >> valueOf(BUS_BOUNDARY_WIDTH);
        return (highIdx > lowIdx);
    endfunction

    rule testInit if (!isInitReg);
        startAddrRandomVal.cntrl.init;
        lengthRandomVal.cntrl.init;
        isInitReg <= True;
        dut.maxReadReqSize.put(tuple2(fromInteger(valueOf(DEFAULT_TLP_SIZE)), fromInteger(valueOf(DEFAULT_TLP_SIZE_WIDTH))));
        $display("INFO: Start Test of mkChunkComputerTb");
        $display("INFO: Set Max Payload Size to ", valueOf(DEFAULT_TLP_SIZE));
    endrule

    rule testInput if (isInitReg && lenRemainReg == 0);
        DmaMemAddr testAddr <- startAddrRandomVal.next;
        DmaReqLen testLength <- lengthRandomVal.next;
        let testEnd = testAddr + zeroExtend(testLength) - 1;
        if (testEnd > testAddr && testEnd <= fromInteger(valueOf(MAX_ADDRESS))) begin 
            let request = DmaExtendRequest{
                startAddr : testAddr,
                endAddr   : testAddr + zeroExtend(testLength),
                length    : testLength,
                tag       : 0
            };
            lenRemainReg <= testLength;
            dut.dmaRequestFifoIn.enq(request);
            // $display("INFO: input ", fshow(request));
        end 
        else begin
            lenRemainReg <= 0;
        end 
    endrule

    rule testOutput if (isInitReg && lenRemainReg > 0);
        let newRequest = dut.chunkRequestFifoOut.first;
        dut.chunkRequestFifoOut.deq;
        immAssert(
            !hasBoundary(newRequest),
            "has boundary assert @ mkChunkComputerTb",
            fshow(newRequest)
        );
        let newRemain = lenRemainReg -  newRequest.length;
        lenRemainReg <= newRemain;
        if (newRemain == 0) begin
            if (epochCntReg < fromInteger(valueOf(CHUNK_PER_EPOCH_TEST_NUM)-1)) begin
                epochCntReg <= epochCntReg + 1;
            end 
            else begin
                epochCntReg <= 0;
                testCntReg <= testCntReg + 1;
                if (testCntReg == fromInteger(valueOf(CHUNK_TX_TEST_SETTING_NUM)-1)) begin
                    $display("INFO: ChunkComputer Test End.");
                    $finish();
                end 
                else begin
                    TlpPayloadSizeWidth mpsWidth = fromInteger(valueOf(DEFAULT_TLP_SIZE_WIDTH)) + truncate(pack(testCntReg));
                    TlpPayloadSize mps = 1 << mpsWidth;
                    dut.maxReadReqSize.put(tuple2(mps, mpsWidth));
                    $display("INFO: Set Max Payload Size to  %d", mps);
                end
            end
        end
    endrule

endmodule

// Do not use any simple tests, run cocotb for whole verification

typedef 25 SIMPLE_TEST_BYTELEN;
typedef 'hABCDEF SIMPLE_TEST_ADDR;

module mkSimpleC2HWriteCoreTb(Empty);
    C2HWriteCore dut <- mkC2HWriteCore(0);
    Reg#(UInt#(32)) testCntReg <- mkReg(0);

    rule testInput if (testCntReg < 1);
        let req = DmaRequest {
            startAddr : fromInteger(valueOf(SIMPLE_TEST_ADDR)),
            length    : fromInteger(valueOf(SIMPLE_TEST_BYTELEN)),
            isWrite   : True
        };
        dut.wrReqFifoIn.enq(req);
        let stream = generatePsuedoStream(fromInteger(valueOf(SIMPLE_TEST_BYTELEN)), True, True);
        dut.dataFifoIn.enq(stream);
        testCntReg <= testCntReg + 1;
    endrule

    rule testOutput;
        let stream = dut.tlpFifoOut.first;
        dut.tlpFifoOut.deq;
        $display(fshow(stream));
        if (stream.isFirst) begin
            let {firstByteEn, lastByteEn} = dut.tlpSideBandFifoOut.first;
            dut.tlpSideBandFifoOut.deq;
            $display("firstByteEn:%b, lastByteEn:%b", firstByteEn, lastByteEn);
            PcieRequesterRequestDescriptor desc = unpack(truncate(stream.data));
            $display("Descriptor Elements: dwordCnt:%d, address:%h", desc.dwordCnt, desc.address << 2);
        end
        if (stream.isLast) begin
            $finish();
        end
    endrule
endmodule

module mkSimpleConvertStraddleAxisToDataStreamTb(Empty);
    ConvertStraddleAxisToDataStream dut <- mkConvertStraddleAxisToDataStream;
    Reg#(UInt#(32)) testCntReg <- mkReg(0);
    Reg#(UInt#(32)) tlpNumReg  <- mkReg(2);

    CmplByteCnt testLength = 20;
    DmaMemAddr startAddr = fromInteger(valueOf(SIMPLE_TEST_ADDR));

    rule testInput if (testCntReg < 1);
        let desc0 = PcieRequesterCompleteDescriptor {
            reserve0            : 0,
            attributes          : 0,
            trafficClass        : 0,
            reserve1            : 0,
            completerId         : 123,
            tag                 : 'b01100,
            requesterId         : 0,
            reserve2            : 0,
            isPoisoned          : False,
            status              : fromInteger(valueOf(SUCCESSFUL_CMPL)),
            dwordCnt            : 1,
            reserve3            : 0,
            isRequestCompleted  : True,
            isLockedReadCmpl    : False,
            byteCnt             : testLength,
            errorcode           : 0,
            lowerAddr           : truncate(startAddr)
        };
        let desc1 = desc0;
        desc1.lowerAddr = desc0.lowerAddr + truncate(testLength);
        desc1.tag = 'b10001;
        let stream = generatePsuedoStream(unpack(zeroExtend(testLength)), True, True);
        let isSop = PcieTlpCtlIsSopReqCpl {
            isSop       :  fromInteger(valueOf(DOUBLE_TLP_IN_THIS_BEAT)),
            isSopPtrs   : replicate(0)
        };
        isSop.isSopPtrs[0] = fromInteger(valueOf(ISSOP_LANE_0));
        isSop.isSopPtrs[1] = fromInteger(valueOf(ISSOP_LANE_32));
        let isEop = PcieTlpCtlIsEopReqCpl {
            isEop       : fromInteger(valueOf(DOUBLE_TLP_IN_THIS_BEAT)),
            isEopPtrs   : replicate(0)
        };
        let data0 = stream.data << valueOf(DES_RC_DESCRIPTOR_WIDTH) | zeroExtend(pack(desc0));
        let data1 = stream.data << valueOf(DES_RC_DESCRIPTOR_WIDTH) | zeroExtend(pack(desc1));
        let byteEn = stream.byteEn << valueOf(TDiv#(DES_RC_DESCRIPTOR_WIDTH, BYTE_WIDTH));
        let sideBand = PcieRequesterCompleteSideBandFrame {
            parity : 0,
            discontinue : False,
            isEop  : isEop,
            isSop  : isSop,
            dataByteEn : byteEn | byteEn << valueOf(STRADDLE_THRESH_BYTE_WIDTH)
        }; 
        
        let axiStream = ReqCmplAxiStream {
            tData :  data0 | data1 << valueOf(STRADDLE_THRESH_BIT_WIDTH),
            tKeep : -1,
            tLast : True,
            tUser : pack(sideBand)
        };
        dut.axiStreamFifoIn.enq(axiStream);
        testCntReg <= testCntReg + 1;
    endrule

    rule testOutput;
        for (Integer pathIdx = 0; pathIdx < valueOf(DMA_PATH_NUM); pathIdx = pathIdx + 1) begin
            if (dut.dataFifoOut[pathIdx].notEmpty) begin
                let stream = dut.dataFifoOut[pathIdx].first;
                dut.dataFifoOut[pathIdx].deq;
                $display(fshow(stream));
            end
        end
    endrule

endmodule


module mkSimpleConvertDataStreamsToStraddleAxisTb(Empty);
    ConvertDataStreamsToStraddleAxis dut <- mkConvertDataStreamsToStraddleAxis;
    Reg#(UInt#(32)) testCntReg <- mkReg(0);

    rule testInput if (testCntReg < 1);
        let stream = generatePsuedoStream(fromInteger(valueOf(SIMPLE_TEST_BYTELEN)), True, True);
        let sideBandByteEn = tuple2(4'b1111, 4'b1111);
        dut.dataFifoIn[0].enq(stream);
        dut.byteEnFifoIn[0].enq(sideBandByteEn);
        dut.dataFifoIn[1].enq(stream);
        dut.byteEnFifoIn[1].enq(sideBandByteEn);
        testCntReg <= testCntReg + 1;
    endrule

    rule testOutput;
        let axiStream = dut.axiStreamFifoOut.first;
        dut.axiStreamFifoOut.deq;
        $display("tData: %h", axiStream.tData);
        $display("tKeep: %h", axiStream.tKeep);
        PcieRequesterRequestSideBandFrame sideBand = unpack(axiStream.tUser);
        $display("isSop: %d", sideBand.isSop.isSop);
        if (axiStream.tLast) begin
            $finish();
        end
    endrule
endmodule

module mkSimpleC2HReadCoreTb(Empty);
    C2HReadCore dut <- mkC2HReadCore(0);
    Reg#(UInt#(32)) testCntReg <- mkReg(0);

    rule testInput if (testCntReg < 1);
        let req = DmaRequest {
            startAddr : fromInteger(valueOf(SIMPLE_TEST_ADDR)),
            length    : fromInteger(valueOf(SIMPLE_TEST_BYTELEN)),
            isWrite   : False
        };
        dut.rdReqFifoIn.enq(req);
        testCntReg <= testCntReg + 1;
    endrule

    rule testOutput;
        let stream = dut.tlpFifoOut.first;
        dut.tlpFifoOut.deq;
        $display(fshow(stream));
        if (stream.isFirst) begin
            let {firstByteEn, lastByteEn} = dut.tlpSideBandFifoOut.first;
            dut.tlpSideBandFifoOut.deq;
            $display("firstByteEn:%b, lastByteEn:%b", firstByteEn, lastByteEn);
            PcieRequesterRequestDescriptor desc = unpack(truncate(stream.data));
            $display("Descriptor Elements: dwordCnt:%d, address:%h", desc.dwordCnt, desc.address << 2);
        end
        if (stream.isLast) begin
            $finish();
        end
    endrule
endmodule

module simpleWritePathTb(Empty);
    C2HWriteCore c2hWriteCore <- mkC2HWriteCore(0);
    ConvertDataStreamsToStraddleAxis adapter <- mkConvertDataStreamsToStraddleAxis;
    mkConnection(c2hWriteCore.tlpFifoOut, adapter.dataFifoIn[0]);
    mkConnection(c2hWriteCore.tlpSideBandFifoOut, adapter.byteEnFifoIn[0]);
    Reg#(UInt#(32)) testCntReg <- mkReg(0);

    rule testInput if (testCntReg < 1);
        let req = DmaRequest {
            startAddr : fromInteger(valueOf(SIMPLE_TEST_ADDR)),
            length    : fromInteger(valueOf(SIMPLE_TEST_BYTELEN)),
            isWrite   : True
        };
        let stream = generatePsuedoStream(fromInteger(valueOf(SIMPLE_TEST_BYTELEN)), True, True);
        c2hWriteCore.wrReqFifoIn.enq(req);
        c2hWriteCore.dataFifoIn.enq(stream);
        testCntReg <= testCntReg + 1;
    endrule

    rule testOutput;
        let axiStream = adapter.axiStreamFifoOut.first;
        adapter.axiStreamFifoOut.deq;
        $display("tData: %h", axiStream.tData);
        $display("tKeep: %h", axiStream.tKeep);
        PcieRequesterRequestSideBandFrame sideBand = unpack(axiStream.tUser);
        $display("isSop: %d", sideBand.isSop.isSop);
        if (axiStream.tLast) begin
            $finish();
        end
    endrule

endmodule
