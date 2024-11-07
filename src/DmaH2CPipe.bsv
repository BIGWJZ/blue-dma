import FIFOF::*;
import Vector::*;
import RegFile::*;
import ClientServer::*;

import SemiFifo::*;
import PrimUtils::*;
import PcieAxiStreamTypes::*;
import PcieTypes::*;
import PcieDescriptorTypes::*;
import PcieAdapter::*;
import DmaTypes::*;

typedef 1 IDEA_CQ_CSR_DWORD_CNT;
typedef 1 IDEA_CC_CSR_DWORD_CNT;
typedef 4 IDEA_CC_CSR_BYTE_CNT;
typedef 4 IDEA_FIRST_BE_HIGH_VALID_PTR_OF_CSR;

// Wrapper between original dma pipe and blue-rdma style interface
interface BdmaH2CPipe#(numeric type sz_csr_addr, numeric type sz_csr_data);
    // User Ifc
    interface Client#(BdmaUserH2cWrReq#(sz_csr_addr, sz_csr_data), BdmaUserH2cWrResp)  writeClt;
    interface Client#(BdmaUserH2cRdReq#(sz_csr_addr), BdmaUserH2cRdResp#(sz_csr_data)) readClt;

    // Pcie Adapter Ifc
    interface FifoIn#(DataStream)  tlpDataFifoIn;
    interface FifoOut#(DataStream) tlpDataFifoOut;
endinterface

module mkBdmaH2CPipe(BdmaH2CPipe#(sz_csr_addr, sz_csr_data)) 
    provisos(
        Add#(_a, sz_csr_addr, DMA_CSR_ADDR_WIDTH), 
        Add#(_b, sz_csr_data, DMA_CSR_DATA_WIDTH)
    );
    DmaH2CPipe pipe <- mkDmaH2CPipe;
    FIFOF#(BdmaUserH2cWrReq#(sz_csr_addr, sz_csr_data))  wrReqQ  <- mkFIFOF;
    FIFOF#(BdmaUserH2cWrResp) wrRespQ <- mkFIFOF;
    FIFOF#(BdmaUserH2cRdReq#(sz_csr_addr))  rdReqQ  <- mkFIFOF;
    FIFOF#(BdmaUserH2cRdResp#(sz_csr_data)) rdRespQ <- mkFIFOF;

    rule forwardReq;
        let h2cReq = pipe.userReqFifoOut.first;
        pipe.userReqFifoOut.deq;
        if (h2cReq.isWrite) begin
            BdmaUserH2cWrReq#(sz_csr_addr, sz_csr_data) wrReq = BdmaUserH2cWrReq {
                addr: truncate(h2cReq.addr),
                data: truncate(h2cReq.value)
            };
            wrReqQ.enq(wrReq);
        end
        else begin
            BdmaUserH2cRdReq#(sz_csr_addr) rdReq = BdmaUserH2cRdReq {
                addr: truncate(h2cReq.addr)
            };
            rdReqQ.enq(rdReq);
        end
    endrule
    
    rule handleWrResp;
        wrRespQ.deq;
    endrule

    rule handleRdResp;
        let value = rdRespQ.first.data;
        rdRespQ.deq;
        pipe.userRespFifoIn.enq(CsrResponse{
            addr : 0,
            value: zeroExtend(value)
        });
    endrule

    interface writeClt = toGPClient(wrReqQ, wrRespQ);
    interface readClt  = toGPClient(rdReqQ, rdRespQ);
    interface tlpDataFifoIn  = pipe.tlpDataFifoIn;
    interface tlpDataFifoOut = pipe.tlpDataFifoOut;
endmodule


function CsrResponse getEmptyCsrResponse();
    return CsrResponse {
        addr  : 0,
        value : 0
    };
endfunction

interface DmaH2CPipe;
    // DMA Internal Csr
    interface FifoOut#(CsrRequest)  csrReqFifoOut;
    interface FifoIn#(CsrResponse)  csrRespFifoIn;
    // User Ifc
    interface FifoOut#(CsrRequest)  userReqFifoOut;
    interface FifoIn#(CsrResponse)  userRespFifoIn;
    // Pcie Adapter Ifc
    interface FifoIn#(DataStream)  tlpDataFifoIn;
    interface FifoOut#(DataStream) tlpDataFifoOut;
    // TODO: Cfg Ifc
endinterface

(* synthesize *)
module mkDmaH2CPipe(DmaH2CPipe);
    
    FIFOF#(DataStream)  tlpInFifo    <- mkFIFOF;
    FIFOF#(DataStream)  tlpOutFifo   <- mkFIFOF;

    FIFOF#(CsrRequest)   reqOutFifo   <- mkFIFOF;
    FIFOF#(CsrResponse)  respInFifo   <- mkFIFOF;

    FIFOF#(CsrRequest)   userOutFifo   <- mkFIFOF;
    FIFOF#(CsrResponse)  userInFifo    <- mkFIFOF;

    FIFOF#(Tuple2#(CsrRequest, PcieCompleterRequestDescriptor)) pendingFifo <- mkSizedFIFOF(valueOf(CMPL_NPREQ_INFLIGHT_NUM));

    function PcieCompleterRequestDescriptor getDescriptorFromFirstBeat(DataStream stream);
        return unpack(truncate(stream.data));
    endfunction

    function Data getDataFromFirstBeat(DataStream stream);
        return stream.data >> valueOf(DES_CQ_DESCRIPTOR_WIDTH);
    endfunction

    Reg#(Bool) isInPacket <- mkReg(False);
    Reg#(UInt#(32)) illegalPcieReqCntReg <- mkReg(0);

    DataBytePtr csrCmplBytes = fromInteger(valueOf(TDiv#(TAdd#(DES_CC_DESCRIPTOR_WIDTH ,DMA_CSR_DATA_WIDTH), BYTE_WIDTH)));

    // This function returns DW addr pointing to inner registers, where byteAddr = DWordAddr << 2
    // The registers in the hw are all of 32bit DW type
    function DmaCsrAddr getCsrAddrFromCqDescriptor(PcieCompleterRequestDescriptor descriptor);
        // Only care about low bits, because the offset is allocated. 
        let addr = getAddrLowBits(zeroExtend(descriptor.address), descriptor.barAperture);
        return truncate(addr);
    endfunction

    rule parseTlp;
        tlpInFifo.deq;
        let stream = tlpInFifo.first;
        isInPacket <= !stream.isLast;
        if (!isInPacket) begin
            let descriptor  = getDescriptorFromFirstBeat(stream);
            case (descriptor.reqType) 
                fromInteger(valueOf(MEM_WRITE_REQ)): begin
                    // $display($time, "ns SIM INFO @ mkDmaH2CPipe: MemWrite Detect!");
                    let firstData = getDataFromFirstBeat(stream);
                    DmaCsrValue wrValue = truncate(firstData);
                    let wrAddr = getCsrAddrFromCqDescriptor(descriptor);
                    if (descriptor.dwordCnt == fromInteger(valueOf(IDEA_CQ_CSR_DWORD_CNT))) begin
                        // $display($time, "ns SIM INFO @ mkDmaH2CPipe: Valid wrReq with Addr %d, data %h", wrAddr, wrValue);
                        let req = CsrRequest {
                            addr      : wrAddr,
                            value     : wrValue,
                            isWrite   : True
                        };
                        if (descriptor.barId == 0) begin
                            reqOutFifo.enq(req);
                        end
                        else if (descriptor.barId == 1) begin
                            userOutFifo.enq(req);
                        end
                    end
                    else begin
                        $display($time, "ns SIM INFO @ mkDmaH2CPipe: Invalid wrReq with Addr %d, data %h", wrAddr, wrValue);
                        illegalPcieReqCntReg <= illegalPcieReqCntReg + 1;
                    end
                end
                fromInteger(valueOf(MEM_READ_REQ)): begin
                    // $display($time, "ns SIM INFO @ mkDmaH2CPipe: MemRead Detect!");
                    let rdAddr = getCsrAddrFromCqDescriptor(descriptor);
                    let req = CsrRequest{
                        addr      : rdAddr,
                        value     : 0,
                        isWrite   : False
                    };
                    $display($time, "ns SIM INFO @ mkDmaH2CPipe: Valid rdReq with Addr %h", rdAddr << valueOf(TLog#(DWORD_BYTES)));
                    if (descriptor.barId == 0) begin
                        reqOutFifo.enq(req);
                    end
                    else if (descriptor.barId == 1) begin
                        userOutFifo.enq(req);
                    end
                    pendingFifo.enq(tuple2(req, descriptor));
                end
                default: illegalPcieReqCntReg <= illegalPcieReqCntReg + 1;
            endcase
        end
    endrule

    rule genTlp;
        CsrResponse resp = getEmptyCsrResponse;
        if (respInFifo.notEmpty) begin
            resp = respInFifo.first;
            respInFifo.deq;
        end
        else if (userInFifo.notEmpty) begin
            resp = userInFifo.first;
            userInFifo.deq;
        end
        let addr = resp.addr;
        let value = resp.value;
        let {req, cqDescriptor} = pendingFifo.first;
        `ifdef H2C_DEBUG
        if (addr == req.addr) begin
            $display($time, "ns SIM INFO @ mkDmaH2CPipe: Valid rdResp with Addr %h, data %h", addr, value);
        `endif
            pendingFifo.deq;
            let ccDescriptor = PcieCompleterCompleteDescriptor {
                reserve0        : 0,
                attributes      : cqDescriptor.attributes,
                trafficClass    : cqDescriptor.trafficClass,
                completerIdEn   : False,
                completerId     : 0,
                tag             : cqDescriptor.tag,
                requesterId     : cqDescriptor.requesterId,
                reserve1        : 0,
                isPoisoned      : False,
                status          : fromInteger(valueOf(DES_CC_STAUS_SUCCESS)),
                dwordCnt        : fromInteger(valueOf(IDEA_CC_CSR_DWORD_CNT)),
                reserve2        : 0,
                isLockedReadCmpl: False,
                byteCnt         : fromInteger(valueOf(IDEA_CC_CSR_BYTE_CNT)),
                reserve3        : 0,
                addrType        : cqDescriptor.addrType,
                reserve4        : 0,
                lowerAddr       : truncate(req.addr << valueOf(TLog#(DWORD_BYTES)))  // Suppose all cq/cc requests are 32 bit aligned
            };
            Data data = zeroExtend(pack(ccDescriptor));
            data = data | (zeroExtend(value) << valueOf(DES_CC_DESCRIPTOR_WIDTH));
            let stream = DataStream {
                data    : data,
                byteEn  : convertBytePtr2ByteEn(csrCmplBytes),
                isFirst : True,
                isLast  : True
            };
            tlpOutFifo.enq(stream);
        `ifdef H2C_DEBUG
            $display($time, "ns SIM INFO @ mkDmaH2CPipe: output a cmpl tlp", fshow(stream));
        end
        else begin
            $display($time, "ns SIM ERROR @ mkDmaH2CPipe: InValid rdResp with Addr %h, data %h and Expect Addr %h", addr, value, req.addr);
        end
        `endif
    endrule

    // DMA Csr Ifc
    interface csrReqFifoOut  = convertFifoToFifoOut(reqOutFifo);
    interface csrRespFifoIn  = convertFifoToFifoIn(respInFifo);
    // User Ifc
    interface userReqFifoOut = convertFifoToFifoOut(userOutFifo);
    interface userRespFifoIn = convertFifoToFifoIn(userInFifo);
    // Pcie Adapter Ifc
    interface tlpDataFifoIn  = convertFifoToFifoIn(tlpInFifo);
    interface tlpDataFifoOut = convertFifoToFifoOut(tlpOutFifo);
endmodule



