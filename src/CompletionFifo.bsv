import GetPut::*;
import Counter::*;
import FIFOF::*;
import BRAMFIFO::*;
import Vector::*;
import DReg::*;
import Connectable::*;

import SemiFifo::*;

// CompletionFifo
//
// A CompletionFifo is like a CompletionBuffer
// but uses Fifos instead of RegFile.
// CompletionFifo can reorder interlaced chunks belong to different streams.

// Example
// reserve a token    : slot = CRam.reserve.get;
// receive a chunk    : CRam.append.enq(tuple2(slot, chunk));
// all chunks received: CRam.complete.put(slot);
// get chunks in order: CRam.drain.first; CRam.drain.deq;

// Parameters:
//  nSlot : slot numbers, should be less than 16 in current version
//  nChunk: chunk numbers per slot, a large value may cause bad timing
//  tChunk: chunk data types
interface CompletionFifo#(numeric type nSlot, type tChunk);
    interface Get#(SlotNum#(nSlot)) reserve;
    method    Bool available;
    interface FifoIn#(Tuple2#(SlotNum#(nSlot), tChunk)) append;
    interface Put#(SlotNum#(nSlot)) complete;
    interface FifoOut#(tChunk) drain;
endinterface

typedef Bit#(TLog#(nSlot)) SlotNum#(numeric type nSlot);

function Bool isPowerOf2(Integer n);
   return (n == (2 ** (log2(n))));
endfunction

module mkCompletionFifo#(Integer nChunk)(CompletionFifo#(nSlot, tChunk))
  provisos (Bits#(tChunk, szChunk), Add#(1, _a, szChunk), Add#(_b, TLog#(nSlot), 4));

    let maxSlotIdx = fromInteger(valueOf(nSlot) - 1);
    function Action incrSlotIdx(Reg#(Bit#(TLog#(nSlot))) idxReg);
        action
            if (isPowerOf2(valueOf(nSlot)))
                idxReg <= idxReg + 1;  // counter wraps automagically
            else
                idxReg <= ((idxReg == maxSlotIdx) ? 0 : idxReg + 1);
        endaction
    endfunction

    FIFOF#(Tuple2#(SlotNum#(nSlot), tChunk)) appendFifo <- mkFIFOF;
    Demux1To16#(tChunk) demuxer <- mkDemux1To16;
    FIFOF#(tChunk) drainFifo <- mkFIFOF;
    Vector#(nSlot, FIFOF#(tChunk)) bufferFifos <- replicateM(mkSizedBRAMFIFOF(nChunk));
    Vector#(nSlot, FIFOF#(Maybe#(tChunk))) fanoutFifos <- replicateM(mkFIFOF);

    Reg#(SlotNum#(nSlot)) inIdxReg  <- mkReg(0);       // input index, return this value when `reserve` is called
    Reg#(SlotNum#(nSlot)) outIdxReg <- mkReg(0);       // output index, pipeout Fifos[outIdxReg] 
    Counter#(TAdd#(1, TLog#(nSlot))) counter <- mkCounter(0);             // number of filled slots
    Reg#(Vector#(nSlot, Bool)) flagsReg <- mkReg(replicate(False));
    Vector#(TAdd#(DEMUX16_LATENCY,1), Reg#(Maybe#(SlotNum#(nSlot)))) cmplSlotRegs <- replicateM(mkDReg(tagged Invalid));
    RWire#(SlotNum#(nSlot)) rstSlot  <- mkRWire;

    Integer fIdx = 0;

    rule writeBuffer;
        let {slot, data} = appendFifo.first;
        appendFifo.deq;
        demuxer.fin.enq(data);
        demuxer.sin.enq(zeroExtend(slot));
    endrule

    for (fIdx = 0; fIdx < valueOf(nSlot); fIdx = fIdx + 1) begin
        mkConnection(demuxer.fouts[fIdx], bufferFifos[fIdx]);
    end

    rule readBuffer;
        if (!bufferFifos[outIdxReg].notEmpty && flagsReg[outIdxReg]) begin  // complete assert and the buffer is empty
            incrSlotIdx(outIdxReg);
            rstSlot.wset(outIdxReg);
            counter.down;
        end
        else begin  
            let data = bufferFifos[outIdxReg].first;
            bufferFifos[outIdxReg].deq;
            drainFifo.enq(data);
        end
    endrule

    rule setFlags;
        let cmplMaybe = cmplSlotRegs[valueOf(DEMUX16_LATENCY)];
        let rstMaybe  = rstSlot.wget;
        let flags = flagsReg;
        if (isValid(cmplMaybe)) begin
            flags[fromMaybe(?, cmplMaybe)] = True;
        end
        if (isValid(rstMaybe)) begin
            flags[fromMaybe(?, rstMaybe)] = False;
        end
        flagsReg <= flags;
    endrule

    rule cmpl;
        for (Integer rIdx = 0; rIdx < valueOf(DEMUX16_LATENCY); rIdx = rIdx + 1) begin
            if (isValid(cmplSlotRegs[rIdx]))
                cmplSlotRegs[rIdx+1] <= cmplSlotRegs[rIdx];
        end
    endrule

    interface Get reserve;
        method ActionValue#(SlotNum#(nSlot)) get() if (counter.value <= maxSlotIdx);
            incrSlotIdx(inIdxReg);
            counter.up;
            return inIdxReg;
        endmethod
    endinterface

    method Bool available();
        return (counter.value <= maxSlotIdx);
    endmethod

    interface Put complete;
        method Action put(SlotNum#(nSlot) slot);
            cmplSlotRegs[0] <= tagged Valid slot;
        endmethod
    endinterface

    interface append = convertFifoToFifoIn(appendFifo);
    interface drain  = convertFifoToFifoOut(drainFifo);

endmodule

function Action demux1To4(FIFOF#(tData) inFifo, Vector#(4, FIFOF#(tData)) outFifos, Bit#(2) s)
    provisos (Bits#(tData, szData));
    action
        let data = inFifo.first;
        inFifo.deq;
        case(s)
            0: outFifos[0].enq(data);
            1: outFifos[1].enq(data);
            2: outFifos[2].enq(data);
            3: outFifos[3].enq(data);
            default: begin end
        endcase
    endaction
endfunction

typedef 3 DEMUX16_LATENCY;

interface Demux1To16#(type tData);
    interface FifoIn#(tData) fin;
    interface Vector#(16, FifoOut#(tData)) fouts;
    interface FifoIn#(Bit#(4)) sin;
endinterface

module mkDemux1To16(Demux1To16#(tData)) provisos(Bits#(tData, szData));
    FIFOF#(tData) inFifo <- mkFIFOF;
    Vector#(4, FIFOF#(tData)) midFifos <- replicateM(mkFIFOF);
    Vector#(4, Vector#(4, FIFOF#(tData))) outFifos <- replicateM(replicateM(mkFIFOF));
    Vector#(2, FIFOF#(Bit#(4))) sFifo <- replicateM(mkFIFOF);

    Vector#(16, FifoOut#(tData)) outIfc = newVector;

    rule l1Demux;
        let l1Set = truncate(sFifo[0].first >> 2);
        demux1To4(inFifo, midFifos, l1Set);
        sFifo[0].deq;
        sFifo[1].enq(sFifo[0].first);
    endrule

    for(Integer idx = 0; idx < 4; idx = idx + 1) begin
        rule l2Demux;
            let l2set = truncate(sFifo[1].first);
            demux1To4(midFifos[idx], outFifos[idx], l2set);
        endrule
    end

    rule sDeq;
        sFifo[1].deq;
    endrule

    for (Integer idx = 0; idx < 4; idx = idx + 1) begin
        for (Integer subIdx = 0; subIdx < 4; subIdx = subIdx + 1) begin
            outIfc[idx*4 + subIdx] = convertFifoToFifoOut(outFifos[idx][subIdx]);
        end
    end

    interface fin = convertFifoToFifoIn(inFifo);
    interface sin = convertFifoToFifoIn(sFifo[0]);
    interface fouts = outIfc;
endmodule
