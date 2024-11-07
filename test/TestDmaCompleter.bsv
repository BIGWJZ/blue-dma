
import FIFOF::*;
import Vector::*;
import FShow::*;

import SemiFifo::*;
import BdmaPrimUtils::*;
import PcieAxiStreamTypes::*;
import PcieTypes::*;
import PcieDescriptorTypes::*;
import DmaTypes::*;
import DmaCompleter::*;
import TestDmacVivado::*;

typedef 'hABCD TEST_DATA; 
typedef 'h1A28 TEST_ADDR;

typedef 2'b10 TRANSLATED_ADDR_TYPE;

typedef 10 READ_TIMEOUT_THRESH;

function PcieTlpCtlIsEopCommon getEmptyEop();
    return PcieTlpCtlIsEopCommon {
        isEopPtrs: replicate(0),
        isEop    : 0
    };
endfunction

function PcieTlpCtlIsSopCommon getEmptySop();
    return PcieTlpCtlIsSopCommon {
        isSopPtrs: replicate(0),
        isSop    : 0
    };
endfunction

function CmplReqAxiStream genPseudoHostRequest(DmaCsrValue testValue, DmaCsrAddr testAddr, Bool isWrite);
    let descriptor = PcieCompleterRequestDescriptor {
        reserve0      : 0,
        attributes    : 0,
        trafficClass  : 0,
        barAperture   : fromInteger(valueOf(DMA_CSR_ADDR_WIDTH)),
        barId         : 0,
        targetFunction: 0,
        tag           : 0,
        requesterId   : fromInteger(valueOf(TEST_DATA)),
        reserve1      : 0,
        reqType       : isWrite ? fromInteger(valueOf(MEM_WRITE_REQ)) :fromInteger(valueOf(MEM_READ_REQ)) ,
        dwordCnt      : 1,
        address       : zeroExtend(testAddr >> valueOf(TSub#(DMA_MEM_ADDR_WIDTH, DES_ADDR_WIDTH))),
        addrType      : fromInteger(valueOf(TRANSLATED_ADDR_TYPE))
    };
    Data data = 0;
    data = data | zeroExtend(pack(descriptor));
    data = data | zeroExtend(testValue) << valueOf(DES_CQ_DESCRIPTOR_WIDTH);
    let sideBand = PcieCompleterRequestSideBandFrame {
        parity          : 0,
        tphSteeringTag  : 0,
        tphType         : 0,
        tphPresent      : 0,
        discontinue     : False,
        isEop           : getEmptyEop,
        isSop           : getEmptySop,
        dataByteEn      : isWrite ? 'hFFF : 'hFF,
        lastByteEn      : 'hF,
        firstByteEn     : 'hF
    };
    return CmplReqAxiStream {
        tData : data,
        tKeep : fromInteger(valueOf(IDEA_CQ_TKEEP_OF_CSR)),
        tLast : True,
        tUser : pack(sideBand)
    };
endfunction

(* doc = "testcase" *) 
module mkTestDmaCompleterRequest(Empty);
    CompleterRequest dut <- mkCompleterRequest;
    Reg#(Bool) isInitReg <- mkReg(False);

    rule testInit if (!isInitReg);
        $display("INFO: Start CompleterRequest test");
        let testAxiStram = genPseudoHostRequest(fromInteger(valueOf(TEST_DATA)), fromInteger(valueOf(TEST_ADDR)), True);
        dut.axiStreamFifoIn.enq(testAxiStram);
        isInitReg <= True;
    endrule

    rule testOutput if (isInitReg);
        dut.csrWriteReqFifoOut.deq;
        let wrReq = dut.csrWriteReqFifoOut.first;
        immAssert(
            (wrReq.addr == fromInteger(valueOf(TEST_ADDR)) && wrReq.value == fromInteger(valueOf(TEST_DATA))),
            "wrReq test @ mkTestDmaCompleterRequest",
            $format("RawReq: Addr %h, Value %h \n But", fromInteger(valueOf(TEST_ADDR)), fromInteger(valueOf(TEST_DATA)),fshow(wrReq))
        );
        $display("INFO: Pass CompleterRequest test");
        $finish();
    endrule

endmodule

(* doc = "testcase" *) 
module mkTestDmaCompleter(Empty);
    TestDmacCsrWrRdLoopTb dut  <- mkTestDmacCsrWrRdLoopTb;
    Reg#(Bool) isInitReg       <- mkReg(False);
    Reg#(Bool) isWriteDoneReg  <- mkReg(False);
    Reg#(Bool) isWriteDoneReg1 <- mkReg(False);
    Reg#(Bool) isReadDoneReg   <- mkReg(False);
    Reg#(UInt#(32)) timeoutReg <- mkReg(0);

    function Action setEmptyRawAxiStream();
        return action
            dut.rawPcie.completerRequest.rawAxiStreamSlave.tValid(
                False,
                0,
                0,
                False,
                0
            );
        endaction;
    endfunction

    rule alwaysEnables;
        dut.rawPcie.completerComplete.rawAxiStreamMaster.tReady(True);
        dut.rawPcie.completerRequest.nonPostedReqCreditCnt(32);
    endrule

    rule testInit;
        if (!isInitReg) begin
            setEmptyRawAxiStream;
            isInitReg <= True;
            $display("INFO: Start Completer test");
        end 
        else if (isInitReg && !isWriteDoneReg) begin
            let testAxiStram = genPseudoHostRequest(fromInteger(valueOf(TEST_DATA)), fromInteger(valueOf(TEST_ADDR)), True);
            dut.rawPcie.completerRequest.rawAxiStreamSlave.tValid(
                True,
                testAxiStram.tData,
                testAxiStram.tKeep,
                testAxiStram.tLast,
                testAxiStram.tUser
            );
            isWriteDoneReg <= True;
        end
        else if (isInitReg && isWriteDoneReg1 && !isReadDoneReg) begin
            let testAxiStram = genPseudoHostRequest(0, fromInteger(valueOf(TEST_ADDR)), False);
            dut.rawPcie.completerRequest.rawAxiStreamSlave.tValid(
                True,
                testAxiStram.tData,
                testAxiStram.tKeep,
                testAxiStram.tLast,
                testAxiStram.tUser
            );
            isReadDoneReg <= True;
        end
        else begin
            setEmptyRawAxiStream;
            isWriteDoneReg1 <= isWriteDoneReg;
        end
    endrule

    rule testOutput if (isInitReg);
        if (timeoutReg > fromInteger(valueOf(READ_TIMEOUT_THRESH))) begin
            $display("Error: no valid cc axiStream out until timeout!");
            $finish();
        end 
        else begin
            if (dut.rawPcie.completerComplete.rawAxiStreamMaster.tValid) begin
                let data = dut.rawPcie.completerComplete.rawAxiStreamMaster.tData;
                let keep = dut.rawPcie.completerComplete.rawAxiStreamMaster.tKeep;
                let isLast = dut.rawPcie.completerComplete.rawAxiStreamMaster.tLast;
                immAssert(
                    (isLast && (keep == 'hF)),
                    "completer output keep&last check @ mkTestDmaCompleter",
                    $format("tKeep: %h, tLast: %h", keep, isLast)
                );
                DmaCsrValue value = truncate(data >> valueOf(DES_CC_DESCRIPTOR_WIDTH));
                immAssert(
                    (value == fromInteger(valueOf(TEST_DATA))),
                    "complete output data check @ mkTestDmaCompleter",
                    $format("write value: %h, read value: %h", valueOf(TEST_DATA), value)
                );
                $display("INFO: Pass Completer test");
                $finish();
            end
            else begin
                timeoutReg <= timeoutReg + 1;
            end
        end
    endrule
endmodule
