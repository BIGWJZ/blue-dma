import FIFOF::*;
import FIFO::*;
import Vector::*;
import Connectable :: *;
import DReg::*;
import GetPut::*;
import BRAMFIFO::*;
import ClientServer::*;

import SemiFifo::*;
import BusConversion::*;
import AxiStreamTypes::*;
import PcieTypes::*;
import PcieConfigurator::*;
import PcieAxiStreamTypes::*;
import PcieAdapter::*;
import DmaTypes::*;  
import DmaUtils::*;
import DmaC2HPipe::*;
import DmaH2CPipe::*;
import SimpleModeUtils::*;
import TestUtils::*;

// For Bsv User
interface BdmaControllerBypassWrapper#(numeric type sz_csr_addr, numeric type sz_csr_data);
    // User Logic Ifc
    interface Server#(BdmaUserC2hWrReq, BdmaUserC2hWrResp) c2hWrSrvA;
    interface Server#(BdmaUserC2hRdReq, BdmaUserC2hRdResp) c2hRdSrvA;
    interface Server#(BdmaUserC2hWrReq, BdmaUserC2hWrResp) c2hWrSrvB;
    interface Server#(BdmaUserC2hRdReq, BdmaUserC2hRdResp) c2hRdSrvB;
    // User Csr Ifc
    interface Client#(BdmaUserH2cWrReq#(sz_csr_addr, sz_csr_data), BdmaUserH2cWrResp)  csrWrClt;
    interface Client#(BdmaUserH2cRdReq#(sz_csr_addr), BdmaUserH2cRdResp#(sz_csr_data)) csrRdClt;

    // Raw PCIe interfaces, connected to the Xilinx PCIe IP
    (* prefix = "" *)interface RawXilinxPcieIp       rawPcie;
endinterface

module mkBdmaControllerBypassWrapper(BdmaControllerBypassWrapper#(sz_csr_addr, sz_csr_data))
    provisos(
        Add#(_a, sz_csr_addr, DMA_CSR_ADDR_WIDTH), 
        Add#(_b, sz_csr_data, DMA_CSR_DATA_WIDTH)
    );
    Wire#(Bool) linkUpWire <- mkWire;
    Reg#(Bool) linkUpReg  <- mkReg(False);
    Reg#(Bool) cfgFlagReg <- mkDReg(False);

    BdmaC2HPipe c2hPipeA <- mkBdmaC2HPipe(0);
    BdmaC2HPipe c2hPipeB <- mkBdmaC2HPipe(1);
    BdmaH2CPipe#(sz_csr_addr, sz_csr_data) h2cPipe  <- mkBdmaH2CPipe;

    RequesterAxiStreamAdapter reqAdapter  <- mkRequesterAxiStreamAdapter;
    CompleterAxiStreamAdapter cmplAdapter <- mkCompleterAxiStreamAdapter;

    PcieConfigurator configurator <- mkPcieConfigurator;

    mkConnection(c2hPipeA.tlpDataFifoOut, reqAdapter.dmaDataFifoIn[0]);
    mkConnection(c2hPipeA.tlpSideBandFifoOut, reqAdapter.dmaSideBandFifoIn[0]);
    mkConnection(reqAdapter.dmaDataFifoOut[0], c2hPipeA.tlpDataFifoIn);

    mkConnection(c2hPipeB.tlpDataFifoOut, reqAdapter.dmaDataFifoIn[1]);
    mkConnection(c2hPipeB.tlpSideBandFifoOut, reqAdapter.dmaSideBandFifoIn[1]);
    mkConnection(reqAdapter.dmaDataFifoOut[1], c2hPipeB.tlpDataFifoIn);

    mkConnection(cmplAdapter.dmaDataFifoOut, h2cPipe.tlpDataFifoIn);
    mkConnection(h2cPipe.tlpDataFifoOut, cmplAdapter.dmaDataFifoIn);

    rule detectLink if (linkUpWire && !linkUpReg);
        configurator.initCfg;
        cfgFlagReg <= True;
        linkUpReg <= True;
        $display($time, "ns SIM INFO @ BLUE-DMAC: PCIe link is up!");
    endrule

    rule setCfg if (cfgFlagReg);
        let tlpSizeCfg <- configurator.tlpSizeCfg.get;
        c2hPipeA.tlpSizeCfg.put(tlpSizeCfg);
        c2hPipeB.tlpSizeCfg.put(tlpSizeCfg);
        $display($time, "ns SIM INFO @ BLUE-DMAC: Get PCIe configurations, mps:%d, mrrs:%d", tlpSizeCfg.mps, tlpSizeCfg.mrrs);
    endrule

    // User Logic Ifc
    interface c2hWrSrvA = c2hPipeA.writeSrv;
    interface c2hRdSrvA = c2hPipeA.readSrv;
    interface c2hWrSrvB = c2hPipeB.writeSrv;
    interface c2hRdSrvB = c2hPipeB.readSrv;
    interface csrWrClt  = h2cPipe.writeClt;
    interface csrRdClt  = h2cPipe.readClt;

    // Raw PCIe Ifc
    interface RawXilinxPcieIp rawPcie;
        interface requesterRequest  = reqAdapter.rawRequesterRequest;
        interface requesterComplete = reqAdapter.rawRequesterComplete;
        interface completerRequest  = cmplAdapter.rawCompleterRequest;
        interface completerComplete = cmplAdapter.rawCompleterComplete;
        interface configuration     = configurator.rawConfiguration;
        method Action linkUp(Bool isLinkUp);
            linkUpWire <= isLinkUp;
        endmethod
    endinterface
endmodule


// Native Blue-DMA Interface, the addrs in the req should be pa
interface DmaController;
    // User Logic Ifc
    interface Vector#(DMA_PATH_NUM, FifoIn#(DataStream))  c2hDataFifoIn;
    interface Vector#(DMA_PATH_NUM, FifoOut#(DataStream)) c2hDataFifoOut;
    interface Vector#(DMA_PATH_NUM, FifoIn#(DmaRequest))  c2hReqFifoIn;

    interface FifoIn#(CsrResponse)  h2cRespFifoIn;
    interface FifoOut#(CsrRequest)  h2cReqFifoOut;

    interface FifoIn#(CsrResponse)  innerRespFifoIn;
    interface FifoOut#(CsrRequest)  innerReqFifoOut;
 
    // Raw PCIe interfaces, connected to the Xilinx PCIe IP
    (* prefix = "" *)interface RawXilinxPcieIp       rawPcie;
endinterface

// TODO : connect Configurator to other modules
(* synthesize *)
module mkDmaController(DmaController);
    Vector#(DMA_PATH_NUM, DmaC2HPipe) c2hPipes = newVector;

    Wire#(Bool) linkUpWire <- mkWire;
    
    Reg#(Bool) linkUpReg  <- mkReg(False);
    Reg#(Bool) cfgFlagReg <- mkDReg(False);

    for (DmaPathNo pathIdx = 0; pathIdx < fromInteger(valueOf(DMA_PATH_NUM)); pathIdx = pathIdx + 1) begin
        c2hPipes[pathIdx] <- mkDmaC2HPipe(pathIdx);
    end
    DmaH2CPipe h2cPipe <- mkDmaH2CPipe;

    RequesterAxiStreamAdapter reqAdapter  <- mkRequesterAxiStreamAdapter;
    CompleterAxiStreamAdapter cmplAdapter <- mkCompleterAxiStreamAdapter;

    PcieConfigurator configurator <- mkPcieConfigurator;

    Vector#(DMA_PATH_NUM, FifoIn#(DataStream))  c2hDataInIfc  = newVector;
    Vector#(DMA_PATH_NUM, FifoOut#(DataStream)) c2hDataOutIfc = newVector;
    Vector#(DMA_PATH_NUM, FifoIn#(DmaRequest))  c2hReqInIfc   = newVector;

    for (DmaPathNo pathIdx = 0; pathIdx < fromInteger(valueOf(DMA_PATH_NUM)); pathIdx = pathIdx + 1) begin
        c2hDataInIfc[pathIdx]  = c2hPipes[pathIdx].wrDataFifoIn;
        c2hDataOutIfc[pathIdx] = c2hPipes[pathIdx].rdDataFifoOut;
        c2hReqInIfc[pathIdx]   = c2hPipes[pathIdx].reqFifoIn;
        mkConnection(c2hPipes[pathIdx].tlpDataFifoOut, reqAdapter.dmaDataFifoIn[pathIdx]);
        mkConnection(c2hPipes[pathIdx].tlpSideBandFifoOut, reqAdapter.dmaSideBandFifoIn[pathIdx]);
        mkConnection(reqAdapter.dmaDataFifoOut[pathIdx], c2hPipes[pathIdx].tlpDataFifoIn);
        rule doneFlag; //TODO: let verilog interface has done signal
            c2hPipes[pathIdx].doneFifoOut.deq;
        endrule
    end

    mkConnection(cmplAdapter.dmaDataFifoOut, h2cPipe.tlpDataFifoIn);
    mkConnection(h2cPipe.tlpDataFifoOut, cmplAdapter.dmaDataFifoIn);

    rule detectLink if (linkUpWire && !linkUpReg);
        configurator.initCfg;
        cfgFlagReg <= True;
        linkUpReg <= True;
        $display($time, "ns SIM INFO @ BLUE-DMAC: PCIe link is up!");
    endrule

    rule setCfg if (cfgFlagReg);
        let tlpSizeCfg <- configurator.tlpSizeCfg.get;
        for (DmaPathNo pathIdx = 0; pathIdx < fromInteger(valueOf(DMA_PATH_NUM)); pathIdx = pathIdx + 1) begin
            c2hPipes[pathIdx].tlpSizeCfg.put(tlpSizeCfg);
        end
        $display($time, "ns SIM INFO @ BLUE-DMAC: Get PCIe configurations, mps:%d, mrrs:%d", tlpSizeCfg.mps, tlpSizeCfg.mrrs);
    endrule

    // User Logic Ifc
    interface c2hDataFifoIn  = c2hDataInIfc;
    interface c2hDataFifoOut = c2hDataOutIfc;
    interface c2hReqFifoIn   = c2hReqInIfc;
    interface h2cRespFifoIn  = h2cPipe.userRespFifoIn;
    interface h2cReqFifoOut  = h2cPipe.userReqFifoOut;
    interface innerRespFifoIn = h2cPipe.csrRespFifoIn;
    interface innerReqFifoOut = h2cPipe.csrReqFifoOut;

    // Raw PCIe Ifc
    interface RawXilinxPcieIp rawPcie;
        interface requesterRequest  = reqAdapter.rawRequesterRequest;
        interface requesterComplete = reqAdapter.rawRequesterComplete;
        interface completerRequest  = cmplAdapter.rawCompleterRequest;
        interface completerComplete = cmplAdapter.rawCompleterComplete;
        interface configuration     = configurator.rawConfiguration;
        method Action linkUp(Bool isLinkUp);
            linkUpWire <= isLinkUp;
        endmethod
    endinterface
endmodule

// For Verilog User

(* always_ready, always_enabled *)
interface RawDmaReqSlave;
    (* prefix = "" *)
    method Action validReq(
        (* port = "valid"    *)     Bool       valid,
        (* port = "start_addr"  *)  DmaMemAddr startAddr,
        (* port = "byte_cnt"  *)    DmaReqLen  length,
        (* port = "is_write"  *)    Bool       isWrite
    );
    (* result = "ready" *) method Bool ready;
endinterface

(* always_ready, always_enabled *)
interface RawDmaCsrMaster;
    (* result = "address" *)  method DmaCsrAddr  address;
    (* result = "value" *)    method DmaCsrValue value;
    (* result = "is_write" *) method Bool        isWrite;
    (* result = "valid" *)    method Bool        valid;
    (* prefix = "" *) method Action ready((* port = "ready" *) Bool rdy);
endinterface

(* always_ready, always_enabled *)
interface RawDmaCsrSlave;
    (* prefix = "" *)
    method Action validResp(
        (* port = "valid"    *)     Bool        valid,
        (* port = "address"  *)     DmaCsrAddr  address,
        (* port = "value"  *)       DmaCsrValue value
    );
    (* result = "ready" *) method Bool ready;
endinterface

typedef TDiv#(DATA_WIDTH, BYTE_WIDTH) DMA_DATA_KEEP_WIDTH;
typedef 1 DMA_DATA_USER_WIDTH;
typedef RawAxiStreamSlave#(DMA_DATA_KEEP_WIDTH, DMA_DATA_USER_WIDTH)  RawDmaDataSlave;
typedef RawAxiStreamMaster#(DMA_DATA_KEEP_WIDTH, DMA_DATA_USER_WIDTH) RawDmaDataMaster;
typedef AxiStream#(DMA_DATA_KEEP_WIDTH, DMA_DATA_USER_WIDTH) DmaAxiStream;

module mkFifoInToRawDmaDataSlave#(FifoIn#(DataStream) pipe)(RawDmaDataSlave);
    Reg#(Bool) isFirstReg <- mkReg(True);
    let rawBus <- mkFifoInToRawBusSlave(pipe);

    method Bool tReady = rawBus.ready;
    method Action tValid(
        Bool valid, 
        Bit#(DATA_WIDTH) tData, 
        Bit#(DMA_DATA_KEEP_WIDTH) tKeep, 
        Bool tLast, 
        Bit#(DMA_DATA_USER_WIDTH) tUser
    );
        if (valid && rawBus.ready) begin
            if (tLast) begin
                isFirstReg <= True;
            end
            else if (isFirstReg) begin
                isFirstReg <= False;
            end
        end
        let stream = DataStream {
            data    : tData,
            byteEn  : tKeep,
            isFirst : isFirstReg && valid,
            isLast  : tLast
        };
        rawBus.validData(valid, stream);
    endmethod
endmodule

module mkFifoOutToRawDmaDataMaster#(FifoOut#(DataStream) pipe)(RawDmaDataMaster);
    let rawBus <- mkFifoOutToRawBusMaster(pipe);
    method Bool tValid = rawBus.valid;
    method Bit#(DATA_WIDTH) tData = rawBus.data.data;
    method Bit#(DMA_DATA_KEEP_WIDTH) tKeep = rawBus.data.byteEn;
    method Bool tLast = rawBus.data.isLast;
    method Bit#(DMA_DATA_USER_WIDTH) tUser = 0;
    method Action tReady(Bool rdy);
        rawBus.ready(rdy);
    endmethod
endmodule

module mkFifoInToRawDmaReqSlave#(FifoIn#(DmaRequest) pipe)(RawDmaReqSlave);
    let rawBus <- mkFifoInToRawBusSlave(pipe);
    method Action validReq(
        Bool       valid,
        DmaMemAddr startAddr,
        DmaReqLen  length,
        Bool       isWrite
    );
        let request = DmaRequest {
            startAddr : startAddr,
            length    : length,
            isWrite   : isWrite
        };
        rawBus.validData(valid, request);
    endmethod
    method Bool ready = rawBus.ready;
endmodule

module mkFifoOutToRawCsrMaster#(FifoOut#(CsrRequest) pipe)(RawDmaCsrMaster);
    let rawBus <- mkFifoOutToRawBusMaster(pipe);
    method DmaCsrAddr  address = rawBus.data.addr;
    method DmaCsrValue value   = rawBus.data.value;
    method Bool        isWrite = rawBus.data.isWrite;
    method Bool        valid   = rawBus.valid;
    method Action ready(Bool rdy);
        rawBus.ready(rdy);
    endmethod
endmodule

module mkFifoInToRawCsrClient#(FifoIn#(CsrResponse) pipe)(RawDmaCsrSlave);
    let rawBus <- mkFifoInToRawBusSlave(pipe);
    method Action validResp(
        Bool        valid,
        DmaCsrAddr  addr,
        DmaCsrValue value
    );
        let resp = CsrResponse {
            addr  : addr,
            value : value
        };
        rawBus.validData(valid, resp);
    endmethod
    method Bool ready = rawBus.ready;
endmodule

// Bypass Mode
// Raw verilog Wrapper of Dma User Logic Ifc
interface RawBypassDmaController;
    // User Logic Ifc
    (* prefix = "s_axis_c2h_0" *)  interface RawDmaDataSlave  dmaWrData0;
    (* prefix = "s_desc_c2h_0" *)  interface RawDmaReqSlave   dmaDesc0;
    (* prefix = "m_axis_c2h_0" *)  interface RawDmaDataMaster dmaRdData0;

    (* prefix = "s_axis_c2h_1" *)  interface RawDmaDataSlave  dmaWrData1;
    (* prefix = "s_desc_c2h_1" *)  interface RawDmaReqSlave   dmaDesc1;
    (* prefix = "m_axis_c2h_1" *)  interface RawDmaDataMaster dmaRdData1;

    (* prefix = "s_h2c_csr" *)     interface RawDmaCsrSlave   dmaCsrResp;
    (* prefix = "m_h2c_csr" *)     interface RawDmaCsrMaster  dmaCsrReq;

    // Raw PCIe interfaces, connected to the Xilinx PCIe IP
    (* prefix = "" *)        interface RawXilinxPcieIp       rawPcie;
endinterface

(* synthesize *)
module mkRawBypassDmaController(RawBypassDmaController);
    DmaController dmac <- mkDmaController;
    GenericCsr    dummyCsr <- mkDummyCsr;

    let dmaWrData0Ifc <- mkFifoInToRawDmaDataSlave(dmac.c2hDataFifoIn[0]);
    let dmaDesc0Ifc   <- mkFifoInToRawDmaReqSlave(dmac.c2hReqFifoIn[0]);
    let dmaRdData0Ifc <- mkFifoOutToRawDmaDataMaster(dmac.c2hDataFifoOut[0]);

    let dmaWrData1Ifc <- mkFifoInToRawDmaDataSlave(dmac.c2hDataFifoIn[1]);
    let dmaDesc1Ifc   <- mkFifoInToRawDmaReqSlave(dmac.c2hReqFifoIn[1]);
    let dmaRdData1Ifc <- mkFifoOutToRawDmaDataMaster(dmac.c2hDataFifoOut[1]);

    let csrRespIfc    <- mkFifoInToRawCsrClient(dmac.h2cRespFifoIn);
    let csrReqIfc     <- mkFifoOutToRawCsrMaster(dmac.h2cReqFifoOut);

    mkConnection(dmac.innerReqFifoOut, dummyCsr.reqFifoIn);
    mkConnection(dummyCsr.respFifoOut, dmac.innerRespFifoIn);
    
    interface dmaWrData0 = dmaWrData0Ifc;
    interface dmaDesc0   = dmaDesc0Ifc;  
    interface dmaRdData0 = dmaRdData0Ifc;
    interface dmaWrData1 = dmaWrData1Ifc;
    interface dmaDesc1   = dmaDesc1Ifc;
    interface dmaRdData1 = dmaRdData1Ifc;
    interface dmaCsrResp = csrRespIfc;
    interface dmaCsrReq  = csrReqIfc;

    interface rawPcie = dmac.rawPcie;
endmodule

interface RawSimpleDmaController;
    // User Logic Ifc
    (* prefix = "s_axis_c2h_0" *)  interface RawDmaDataSlave  dmaWrData0;
    (* prefix = "m_axis_c2h_0" *)  interface RawDmaDataMaster dmaRdData0;

    (* prefix = "s_axis_c2h_1" *)  interface RawDmaDataSlave  dmaWrData1;
    (* prefix = "m_axis_c2h_1" *)  interface RawDmaDataMaster dmaRdData1;

    (* prefix = "s_h2c_csr" *)     interface RawDmaCsrSlave   dmaCsrResp;
    (* prefix = "m_h2c_csr" *)     interface RawDmaCsrMaster  dmaCsrReq;

    // Raw PCIe interfaces, connected to the Xilinx PCIe IP
    (* prefix = "" *)        interface RawXilinxPcieIp       rawPcie;
endinterface

// Simple Mode For Read-Write Loop Testing, which has no external ports
(* synthesize *)
module mkRawSimpleDmaController(RawSimpleDmaController);
    DmaController dmac       <- mkDmaController;
    DmaSimpleCore simpleCore <- mkDmaSimpleCore;

    for (DmaPathNo pathIdx = 0; pathIdx < fromInteger(valueOf(DMA_PATH_NUM)); pathIdx = pathIdx + 1 ) begin
        mkConnection(dmac.c2hReqFifoIn[pathIdx], simpleCore.c2hReqFifoOut[pathIdx]);
    end

    let dmaWrData0Ifc <- mkFifoInToRawDmaDataSlave(dmac.c2hDataFifoIn[0]);
    let dmaRdData0Ifc <- mkFifoOutToRawDmaDataMaster(dmac.c2hDataFifoOut[0]);

    let dmaWrData1Ifc <- mkFifoInToRawDmaDataSlave(dmac.c2hDataFifoIn[1]);
    let dmaRdData1Ifc <- mkFifoOutToRawDmaDataMaster(dmac.c2hDataFifoOut[1]);

    let csrRespIfc    <- mkFifoInToRawCsrClient(dmac.h2cRespFifoIn);
    let csrReqIfc     <- mkFifoOutToRawCsrMaster(dmac.h2cReqFifoOut);

    mkConnection(dmac.innerReqFifoOut, simpleCore.reqFifoIn);
    mkConnection(dmac.innerRespFifoIn, simpleCore.respFifoOut);

    interface rawPcie = dmac.rawPcie;

    interface dmaWrData0 = dmaWrData0Ifc;
    interface dmaRdData0 = dmaRdData0Ifc;
    interface dmaWrData1 = dmaWrData1Ifc;
    interface dmaRdData1 = dmaRdData1Ifc;
    interface dmaCsrResp = csrRespIfc;
    interface dmaCsrReq  = csrReqIfc;
endmodule

interface RawLoopDmaController;
    // User Logic Ifc

    // Raw PCIe interfaces, connected to the Xilinx PCIe IP
    (* prefix = "" *)        interface RawXilinxPcieIp       rawPcie;
endinterface

(* synthesize *)
module mkRawTestDmaController(RawLoopDmaController);
    DmaController dmac       <- mkDmaController;
    DmaSimpleCore simpleCore <- mkDmaSimpleCore;
    GenericCsr    dummyCsr   <- mkDummyCsr;
    Vector#(DMA_PATH_NUM, FIFOF#(DataStream)) dataFifo <- replicateM(mkSizedBRAMFIFOF(valueOf(BUS_BOUNDARY)));

    for (DmaPathNo pathIdx = 0; pathIdx < fromInteger(valueOf(DMA_PATH_NUM)); pathIdx = pathIdx + 1 ) begin
        mkConnection(dataFifo[pathIdx], dmac.c2hDataFifoIn[pathIdx]);
        mkConnection(dmac.c2hDataFifoOut[pathIdx], dataFifo[pathIdx]);
        mkConnection(dmac.c2hReqFifoIn[pathIdx], simpleCore.c2hReqFifoOut[pathIdx]);
    end

    mkConnection(dmac.innerReqFifoOut, simpleCore.reqFifoIn);
    mkConnection(dmac.innerRespFifoIn, simpleCore.respFifoOut);

    mkConnection(dmac.h2cReqFifoOut, dummyCsr.reqFifoIn);
    mkConnection(dmac.h2cRespFifoIn, dummyCsr.respFifoOut);

    rule logRead;
        let stream = dmac.c2hDataFifoOut[0].first;
        $display($time, "ns SIM INFO @ mkRawTestDmaController: recv stream, isFirst %d, isLast %d, data %h", pack(stream.isFirst), pack(stream.isLast), stream.data);
    endrule

    interface rawPcie = dmac.rawPcie;

endmodule
