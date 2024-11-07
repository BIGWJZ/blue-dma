import GetPut::*;
import Counter::*;
import FIFOF::*;
import Randomizable::*;
import LFSR::*;
import Vector::*;

import SemiFifo::*;
import CompletionFifo::*;
import BdmaPrimUtils::*;
import PcieAxiStreamTypes::*;
import DmaTypes::*;

typedef 6 TEST_CHUNK_NUM;
typedef 16 TEST_SLOT_NUM;

typedef Bit#(32) TestData;
typedef Bit#(TLog#(TEST_SLOT_NUM)) TestTag;
typedef Bit#(TLog#(TEST_CHUNK_NUM)) TestReq;
typedef Bit#(8) TimeInterval;

(* doc = "testcase" *) 
module mkCompletionFifoTb(Empty);

    CompletionFifo#(TEST_SLOT_NUM, TestData) dut <- mkCompletionFifo(valueOf(TEST_CHUNK_NUM));
    Randomize#(TestReq) reqGen <- mkConstrainedRandomizer(1, fromInteger(valueOf(TEST_CHUNK_NUM)-1));

    FIFOF#(TestTag) tagFifo <- mkSizedFIFOF(valueOf(TEST_SLOT_NUM));
    FIFOF#(Tuple2#(TestTag, TestReq)) reqFifo <- mkSizedFIFOF(valueOf(TEST_SLOT_NUM));

    Vector#(TEST_SLOT_NUM, Reg#(TestReq)) reqs     <- replicateM(mkReg(0));
    Vector#(TEST_SLOT_NUM, Reg#(TestReq)) reqDones <- replicateM(mkReg(0));
    Vector#(TEST_SLOT_NUM, Reg#(Bool)) doneFlags   <- replicateM(mkReg(True));

    Reg#(Bool)    initReg   <- mkReg(False);
    Reg#(TestTag) outPtrReg <- mkReg(0);
    Reg#(TestData) dataReg  <- mkReg(0);

    Reg#(UInt#(32)) sentChunksReg <- mkReg(0);
    Reg#(UInt#(32)) recvChunksReg <- mkReg(0);

    rule init if (!initReg);
        reqGen.cntrl.init;
        initReg <= True;
    endrule

    rule genRequest if (initReg);    
        if (dut.available) begin
            let tag <- dut.reserve.get;
            tagFifo.enq(tag);
            let reqLen <- reqGen.next;
            reqFifo.enq(tuple2(tag, reqLen));
            sentChunksReg <= sentChunksReg + unpack(zeroExtend(reqLen));
            $display("INFO: Gen Tag %h request %h", tag, reqLen);
        end
    endrule

    rule getResponse if (initReg);
        outPtrReg <= outPtrReg == fromInteger(valueOf(TEST_SLOT_NUM)-1) ? 0 : outPtrReg + 1;
        if (!doneFlags[outPtrReg]) begin
            if (reqDones[outPtrReg] < reqs[outPtrReg]) begin
                reqDones[outPtrReg] <= reqDones[outPtrReg] + 1;
                dut.append.enq(tuple2(outPtrReg, zeroExtend(outPtrReg) << valueOf(TLog#(TEST_SLOT_NUM)) | zeroExtend(reqDones[outPtrReg])));
            end
            else begin         
                $display("Debug: set tag %h done, dones %d, req %d", outPtrReg, reqDones[outPtrReg]-1, reqs[outPtrReg]);
                dut.complete.put(outPtrReg);
                doneFlags[outPtrReg] <= True;
            end 
        end
        else begin
            if (reqFifo.notEmpty) begin
                let {tag, reqLen} = reqFifo.first;
                if (outPtrReg == tag) begin
                    reqDones[outPtrReg]  <= 0;
                    reqs[outPtrReg]      <= reqLen;
                    doneFlags[outPtrReg] <= False;
                    reqFifo.deq;
                end
            end
        end
    endrule

    rule readCompletionFifo if (initReg);
        let data = dut.drain.first;
        dataReg <= data;
        immAssert(
            (data > dataReg || dataReg == 0),
            "order check @ mkCompletionFifoTb",
            $format(data, dataReg)
        );
        dut.drain.deq;
        recvChunksReg <= recvChunksReg + 1;
        $display("Debug: drain from CFifo %h", data);
    endrule

    rule testFinish if (initReg);
        if (recvChunksReg == sentChunksReg && recvChunksReg > 0) begin
            $display("test CompletionFifo end!");
            $finish();
        end
    endrule

endmodule

module mkSimpleCompletionFifoTb(Empty);

    CompletionFifo#(TEST_SLOT_NUM, TestData) dut <- mkCompletionFifo(valueOf(TEST_CHUNK_NUM));
    FIFOF#(TestTag) tagFifo <- mkSizedFIFOF(valueOf(TEST_SLOT_NUM));
    Reg#(Bool) initReg <- mkReg(False);
    Reg#(UInt#(10)) testCntReg <- mkReg(0);
    Reg#(UInt#(10)) testOutReg <- mkReg(0);
    let testNum = 20;


    rule init if (!initReg);
        initReg <= True;
    endrule

    rule genRequest if (initReg && testCntReg <= testNum);    
        if (dut.available) begin
            let tag <- dut.reserve.get;
            tagFifo.enq(tag);
            $display("INFO: Gen Tag %d", tag);
            testCntReg <= testCntReg + 1;
        end
    endrule

    rule getResponse if (initReg);
        let tag = tagFifo.first;
        tagFifo.deq;
        dut.append.enq(tuple2(tag, zeroExtend(tag)*10));
        dut.complete.put(tag);
    endrule

    rule getOrder if (initReg);
        let data = dut.drain.first;
        dut.drain.deq;
        $display("INFO: %d drain %d", testOutReg, data);
        testOutReg <= testOutReg + 1;
        if (testOutReg == fromInteger(testNum)) begin
            $finish();
        end
    endrule

endmodule

interface CFifoInstTb;
    interface Get#(TestTag) reserve;
    interface FifoIn#(Tuple2#(TestTag, DataStream)) append;
    interface Put#(TestTag) complete;
    interface FifoOut#(DataStream) drain;
endinterface

(* synthesize *)
module mkCompletionFifoInst(CFifoInstTb);
    CompletionFifo#(TEST_SLOT_NUM, DataStream) cFifo <- mkCompletionFifo(valueOf(MAX_STREAM_NUM_PER_COMPLETION));
    interface reserve  = cFifo.reserve;
    interface append   = cFifo.append;
    interface complete = cFifo.complete;
    interface drain    = cFifo.drain;
endmodule
