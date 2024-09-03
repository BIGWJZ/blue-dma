import FIFOF::*;
import Vector::*;

import PcieAxiStreamTypes::*;
import DmaTypes::*;

function Action immAssert(Bool condition, String assertName, Fmt assertFmtMsg);
    action
        let pos = printPosition(getStringPosition(assertName));
        // let pos = printPosition(getEvalPosition(condition));
        if (!condition) begin
            $error(
                "ImmAssert failed in %m @time=%0t: %s-- %s: ",
                $time, pos, assertName, assertFmtMsg
            );
            $finish(1);
        end
    endaction
endfunction

function ByteModDWord byteModDWord(Bit#(tSz) bytes) provisos(Add#(_a, BYTE_DWORD_SHIFT_WIDTH, tSz));
    return truncate(bytes);
endfunction

function DataBytePtr convertByteEn2BytePtr (ByteEn byteEn);
    DataBytePtr ptr = 0;
    case(byteEn) matches
        'b0000000000000000000000000000000000000000000000000000000000000001: ptr = 1;
        'b000000000000000000000000000000000000000000000000000000000000001?: ptr = 2;
        'b00000000000000000000000000000000000000000000000000000000000001??: ptr = 3;
        'b0000000000000000000000000000000000000000000000000000000000001???: ptr = 4;
        'b000000000000000000000000000000000000000000000000000000000001????: ptr = 5;
        'b00000000000000000000000000000000000000000000000000000000001?????: ptr = 6;
        'b0000000000000000000000000000000000000000000000000000000001??????: ptr = 7;
        'b000000000000000000000000000000000000000000000000000000001???????: ptr = 8;
        'b00000000000000000000000000000000000000000000000000000001????????: ptr = 9;
        'b0000000000000000000000000000000000000000000000000000001?????????: ptr = 10;
        'b000000000000000000000000000000000000000000000000000001??????????: ptr = 11;
        'b00000000000000000000000000000000000000000000000000001???????????: ptr = 12;
        'b0000000000000000000000000000000000000000000000000001????????????: ptr = 13;
        'b000000000000000000000000000000000000000000000000001?????????????: ptr = 14;
        'b00000000000000000000000000000000000000000000000001??????????????: ptr = 15;
        'b0000000000000000000000000000000000000000000000001???????????????: ptr = 16;
        'b000000000000000000000000000000000000000000000001????????????????: ptr = 17;
        'b00000000000000000000000000000000000000000000001?????????????????: ptr = 18;
        'b0000000000000000000000000000000000000000000001??????????????????: ptr = 19;
        'b000000000000000000000000000000000000000000001???????????????????: ptr = 20;
        'b00000000000000000000000000000000000000000001????????????????????: ptr = 21;
        'b0000000000000000000000000000000000000000001?????????????????????: ptr = 22;
        'b000000000000000000000000000000000000000001??????????????????????: ptr = 23;
        'b00000000000000000000000000000000000000001???????????????????????: ptr = 24;
        'b0000000000000000000000000000000000000001????????????????????????: ptr = 25;
        'b000000000000000000000000000000000000001?????????????????????????: ptr = 26;
        'b00000000000000000000000000000000000001??????????????????????????: ptr = 27;
        'b0000000000000000000000000000000000001???????????????????????????: ptr = 28;
        'b000000000000000000000000000000000001????????????????????????????: ptr = 29;
        'b00000000000000000000000000000000001?????????????????????????????: ptr = 30;
        'b0000000000000000000000000000000001??????????????????????????????: ptr = 31;
        'b000000000000000000000000000000001???????????????????????????????: ptr = 32;
        'b00000000000000000000000000000001????????????????????????????????: ptr = 33;
        'b0000000000000000000000000000001?????????????????????????????????: ptr = 34;
        'b000000000000000000000000000001??????????????????????????????????: ptr = 35;
        'b00000000000000000000000000001???????????????????????????????????: ptr = 36;
        'b0000000000000000000000000001????????????????????????????????????: ptr = 37;
        'b000000000000000000000000001?????????????????????????????????????: ptr = 38;
        'b00000000000000000000000001??????????????????????????????????????: ptr = 39;
        'b0000000000000000000000001???????????????????????????????????????: ptr = 40;
        'b000000000000000000000001????????????????????????????????????????: ptr = 41;
        'b00000000000000000000001?????????????????????????????????????????: ptr = 42;
        'b0000000000000000000001??????????????????????????????????????????: ptr = 43;
        'b000000000000000000001???????????????????????????????????????????: ptr = 44;
        'b00000000000000000001????????????????????????????????????????????: ptr = 45;
        'b0000000000000000001?????????????????????????????????????????????: ptr = 46;
        'b000000000000000001??????????????????????????????????????????????: ptr = 47;
        'b00000000000000001???????????????????????????????????????????????: ptr = 48;
        'b0000000000000001????????????????????????????????????????????????: ptr = 49;
        'b000000000000001?????????????????????????????????????????????????: ptr = 50;
        'b00000000000001??????????????????????????????????????????????????: ptr = 51;
        'b0000000000001???????????????????????????????????????????????????: ptr = 52;
        'b000000000001????????????????????????????????????????????????????: ptr = 53;
        'b00000000001?????????????????????????????????????????????????????: ptr = 54;
        'b0000000001??????????????????????????????????????????????????????: ptr = 55;
        'b000000001???????????????????????????????????????????????????????: ptr = 56;
        'b00000001????????????????????????????????????????????????????????: ptr = 57;
        'b0000001?????????????????????????????????????????????????????????: ptr = 58;
        'b000001??????????????????????????????????????????????????????????: ptr = 59;
        'b00001???????????????????????????????????????????????????????????: ptr = 60;
        'b0001????????????????????????????????????????????????????????????: ptr = 61;
        'b001?????????????????????????????????????????????????????????????: ptr = 62;
        'b01??????????????????????????????????????????????????????????????: ptr = 63;
        'b1???????????????????????????????????????????????????????????????: ptr = 64;
        default                                                           : ptr = 0;
    endcase
    return ptr;
endfunction

function ByteEn convertBytePtr2ByteEn (DataBytePtr bytePtr);
    ByteEn byteEn = 0;
    case(bytePtr)
         1 : byteEn = 'h0000000000000001;
         2 : byteEn = 'h0000000000000003;
         3 : byteEn = 'h0000000000000007;
         4 : byteEn = 'h000000000000000F;
         5 : byteEn = 'h000000000000001F;
         6 : byteEn = 'h000000000000003F;
         7 : byteEn = 'h000000000000007F;
         8 : byteEn = 'h00000000000000FF;
         9 : byteEn = 'h00000000000001FF;
        10 : byteEn = 'h00000000000003FF;
        11 : byteEn = 'h00000000000007FF;
        12 : byteEn = 'h0000000000000FFF;
        13 : byteEn = 'h0000000000001FFF;
        14 : byteEn = 'h0000000000003FFF;
        15 : byteEn = 'h0000000000007FFF;
        16 : byteEn = 'h000000000000FFFF;
        17 : byteEn = 'h000000000001FFFF;
        18 : byteEn = 'h000000000003FFFF;
        19 : byteEn = 'h000000000007FFFF;
        20 : byteEn = 'h00000000000FFFFF;
        21 : byteEn = 'h00000000001FFFFF;
        22 : byteEn = 'h00000000003FFFFF;
        23 : byteEn = 'h00000000007FFFFF;
        24 : byteEn = 'h0000000000FFFFFF;
        25 : byteEn = 'h0000000001FFFFFF;
        26 : byteEn = 'h0000000003FFFFFF;
        27 : byteEn = 'h0000000007FFFFFF;
        28 : byteEn = 'h000000000FFFFFFF;
        29 : byteEn = 'h000000001FFFFFFF;
        30 : byteEn = 'h000000003FFFFFFF;
        31 : byteEn = 'h000000007FFFFFFF;
        32 : byteEn = 'h00000000FFFFFFFF;
        33 : byteEn = 'h00000001FFFFFFFF;
        34 : byteEn = 'h00000003FFFFFFFF;
        35 : byteEn = 'h00000007FFFFFFFF;
        36 : byteEn = 'h0000000FFFFFFFFF;
        37 : byteEn = 'h0000001FFFFFFFFF;
        38 : byteEn = 'h0000003FFFFFFFFF;
        39 : byteEn = 'h0000007FFFFFFFFF;
        40 : byteEn = 'h000000FFFFFFFFFF;
        41 : byteEn = 'h000001FFFFFFFFFF;
        42 : byteEn = 'h000003FFFFFFFFFF;
        43 : byteEn = 'h000007FFFFFFFFFF;
        44 : byteEn = 'h00000FFFFFFFFFFF;
        45 : byteEn = 'h00001FFFFFFFFFFF;
        46 : byteEn = 'h00003FFFFFFFFFFF;
        47 : byteEn = 'h00007FFFFFFFFFFF;
        48 : byteEn = 'h0000FFFFFFFFFFFF;
        49 : byteEn = 'h0001FFFFFFFFFFFF;
        50 : byteEn = 'h0003FFFFFFFFFFFF;
        51 : byteEn = 'h0007FFFFFFFFFFFF;
        52 : byteEn = 'h000FFFFFFFFFFFFF;
        53 : byteEn = 'h001FFFFFFFFFFFFF;
        54 : byteEn = 'h003FFFFFFFFFFFFF;
        55 : byteEn = 'h007FFFFFFFFFFFFF;
        56 : byteEn = 'h00FFFFFFFFFFFFFF;
        57 : byteEn = 'h01FFFFFFFFFFFFFF;
        58 : byteEn = 'h03FFFFFFFFFFFFFF;
        59 : byteEn = 'h07FFFFFFFFFFFFFF;
        60 : byteEn = 'h0FFFFFFFFFFFFFFF;
        61 : byteEn = 'h1FFFFFFFFFFFFFFF;
        62 : byteEn = 'h3FFFFFFFFFFFFFFF;
        63 : byteEn = 'h7FFFFFFFFFFFFFFF;
        64 : byteEn = 'hFFFFFFFFFFFFFFFF;
        default           : byteEn = 0;
    endcase
    return byteEn;
endfunction

function DWordByteEn convertDWordOffset2FirstByteEn (ByteModDWord dwOffset);
    DWordByteEn dwByteEn = 0;
    case(dwOffset)
        0: dwByteEn = 'b1111;
        1: dwByteEn = 'b1110;
        2: dwByteEn = 'b1100;
        3: dwByteEn = 'b1000;
        default: dwByteEn = 'b0000;
    endcase
    return dwByteEn;
endfunction

function DWordByteEn convertDWordOffset2LastByteEn (ByteModDWord dwOffset);
    DWordByteEn dwByteEn = 0;
    case(dwOffset)
        0: dwByteEn = 'b0001;
        1: dwByteEn = 'b0011;
        2: dwByteEn = 'b0111;
        3: dwByteEn = 'b1111;
        default: dwByteEn = 'b0000;
    endcase
    return dwByteEn;
endfunction

function Data selectDataByByteMask (Data data, ByteEn byteEn);
    Data result = 0;
    for (Integer byteIdx = 0; byteIdx < valueOf(BYTE_EN_WIDTH); byteIdx = byteIdx + 1) begin
        let bitIdxLo = byteIdx * valueOf(BYTE_WIDTH);
        let bitIdxHi = (byteIdx + 1) * valueOf(BYTE_WIDTH) - 1;
        if (byteEn[byteIdx] == 1'b1) begin
           result[bitIdxHi:bitIdxLo] = Byte'(data[bitIdxHi:bitIdxLo]);
        end
    end
    return result;
endfunction

// DWordPtr strarts from 0 not 1 to align to PcieTlpIsEop
function DataDwordPtr convertByteEn2DwordPtr (ByteEn byteEn);
    DataDwordPtr ptr = 0;
    case(byteEn) matches
        'b0000000000000000000000000000000000000000000000000000000000000001: ptr = 0;
        'b000000000000000000000000000000000000000000000000000000000000001?: ptr = 0;
        'b00000000000000000000000000000000000000000000000000000000000001??: ptr = 0;
        'b0000000000000000000000000000000000000000000000000000000000001???: ptr = 0;
        'b000000000000000000000000000000000000000000000000000000000001????: ptr = 1;
        'b00000000000000000000000000000000000000000000000000000000001?????: ptr = 1;
        'b0000000000000000000000000000000000000000000000000000000001??????: ptr = 1;
        'b000000000000000000000000000000000000000000000000000000001???????: ptr = 1;
        'b00000000000000000000000000000000000000000000000000000001????????: ptr = 2;
        'b0000000000000000000000000000000000000000000000000000001?????????: ptr = 2;
        'b000000000000000000000000000000000000000000000000000001??????????: ptr = 2;
        'b00000000000000000000000000000000000000000000000000001???????????: ptr = 2;
        'b0000000000000000000000000000000000000000000000000001????????????: ptr = 3;
        'b000000000000000000000000000000000000000000000000001?????????????: ptr = 3;
        'b00000000000000000000000000000000000000000000000001??????????????: ptr = 3;
        'b0000000000000000000000000000000000000000000000001???????????????: ptr = 3;
        'b000000000000000000000000000000000000000000000001????????????????: ptr = 4;
        'b00000000000000000000000000000000000000000000001?????????????????: ptr = 4;
        'b0000000000000000000000000000000000000000000001??????????????????: ptr = 4;
        'b000000000000000000000000000000000000000000001???????????????????: ptr = 4;
        'b00000000000000000000000000000000000000000001????????????????????: ptr = 5;
        'b0000000000000000000000000000000000000000001?????????????????????: ptr = 5;
        'b000000000000000000000000000000000000000001??????????????????????: ptr = 5;
        'b00000000000000000000000000000000000000001???????????????????????: ptr = 5;
        'b0000000000000000000000000000000000000001????????????????????????: ptr = 6;
        'b000000000000000000000000000000000000001?????????????????????????: ptr = 6;
        'b00000000000000000000000000000000000001??????????????????????????: ptr = 6;
        'b0000000000000000000000000000000000001???????????????????????????: ptr = 6;
        'b000000000000000000000000000000000001????????????????????????????: ptr = 7;
        'b00000000000000000000000000000000001?????????????????????????????: ptr = 7;
        'b0000000000000000000000000000000001??????????????????????????????: ptr = 7;
        'b000000000000000000000000000000001???????????????????????????????: ptr = 7;
        'b00000000000000000000000000000001????????????????????????????????: ptr = 8;
        'b0000000000000000000000000000001?????????????????????????????????: ptr = 8;
        'b000000000000000000000000000001??????????????????????????????????: ptr = 8;
        'b00000000000000000000000000001???????????????????????????????????: ptr = 8;
        'b0000000000000000000000000001????????????????????????????????????: ptr = 9;
        'b000000000000000000000000001?????????????????????????????????????: ptr = 9;
        'b00000000000000000000000001??????????????????????????????????????: ptr = 9;
        'b0000000000000000000000001???????????????????????????????????????: ptr = 9;
        'b000000000000000000000001????????????????????????????????????????: ptr = 10;
        'b00000000000000000000001?????????????????????????????????????????: ptr = 10;
        'b0000000000000000000001??????????????????????????????????????????: ptr = 10;
        'b000000000000000000001???????????????????????????????????????????: ptr = 10;
        'b00000000000000000001????????????????????????????????????????????: ptr = 11;
        'b0000000000000000001?????????????????????????????????????????????: ptr = 11;
        'b000000000000000001??????????????????????????????????????????????: ptr = 11;
        'b00000000000000001???????????????????????????????????????????????: ptr = 11;
        'b0000000000000001????????????????????????????????????????????????: ptr = 12;
        'b000000000000001?????????????????????????????????????????????????: ptr = 12;
        'b00000000000001??????????????????????????????????????????????????: ptr = 12;
        'b0000000000001???????????????????????????????????????????????????: ptr = 12;
        'b000000000001????????????????????????????????????????????????????: ptr = 13;
        'b00000000001?????????????????????????????????????????????????????: ptr = 13;
        'b0000000001??????????????????????????????????????????????????????: ptr = 13;
        'b000000001???????????????????????????????????????????????????????: ptr = 13;
        'b00000001????????????????????????????????????????????????????????: ptr = 14;
        'b0000001?????????????????????????????????????????????????????????: ptr = 14;
        'b000001??????????????????????????????????????????????????????????: ptr = 14;
        'b00001???????????????????????????????????????????????????????????: ptr = 14;
        'b0001????????????????????????????????????????????????????????????: ptr = 15;
        'b001?????????????????????????????????????????????????????????????: ptr = 15;
        'b01??????????????????????????????????????????????????????????????: ptr = 15;
        'b1???????????????????????????????????????????????????????????????: ptr = 15;
        default           : ptr = 0;
    endcase
    return ptr;
endfunction

function Data getDataLowBytes(Data data, DataBytePtr ptr);
    Data temp = 0;
    case(ptr)
        1 : temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*1 -1 : 0]));
        2 : temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*2 -1 : 0]));
        3 : temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*3 -1 : 0]));
        4 : temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*4 -1 : 0]));
        5 : temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*5 -1 : 0]));
        6 : temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*6 -1 : 0]));
        7 : temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*7 -1 : 0]));
        8 : temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*8 -1 : 0]));
        9 : temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*9 -1 : 0]));
        10: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*10-1 : 0]));
        11: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*11-1 : 0]));
        12: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*12-1 : 0]));
        13: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*13-1 : 0]));
        14: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*14-1 : 0]));
        15: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*15-1 : 0]));
        16: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*16-1 : 0]));
        17: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*17-1 : 0]));
        18: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*18-1 : 0]));
        19: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*19-1 : 0]));
        20: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*20-1 : 0]));
        21: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*21-1 : 0]));
        22: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*22-1 : 0]));
        23: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*23-1 : 0]));
        24: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*24-1 : 0]));
        25: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*25-1 : 0]));
        26: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*26-1 : 0]));
        27: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*27-1 : 0]));
        28: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*28-1 : 0]));
        29: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*29-1 : 0]));
        30: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*30-1 : 0]));
        31: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*31-1 : 0]));
        32: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*32-1 : 0]));
        33: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*33-1 : 0]));
        34: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*34-1 : 0]));
        35: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*35-1 : 0]));
        36: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*36-1 : 0]));
        37: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*37-1 : 0]));
        38: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*38-1 : 0]));
        39: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*39-1 : 0]));
        40: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*40-1 : 0]));
        41: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*41-1 : 0]));
        42: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*42-1 : 0]));
        43: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*43-1 : 0]));
        44: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*44-1 : 0]));
        45: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*45-1 : 0]));
        46: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*46-1 : 0]));
        47: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*47-1 : 0]));
        48: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*48-1 : 0]));
        49: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*49-1 : 0]));
        50: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*50-1 : 0]));
        51: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*51-1 : 0]));
        52: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*52-1 : 0]));
        53: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*53-1 : 0]));
        54: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*54-1 : 0]));
        55: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*55-1 : 0]));
        56: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*56-1 : 0]));
        57: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*57-1 : 0]));
        58: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*58-1 : 0]));
        59: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*59-1 : 0]));
        60: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*60-1 : 0]));
        61: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*61-1 : 0]));
        62: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*62-1 : 0]));
        63: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*63-1 : 0]));
        64: temp = zeroExtend(Data'(data[valueOf(BYTE_WIDTH)*64-1 : 0]));
        default: temp = 0;
    endcase
    return temp;
endfunction

function DmaMemAddr getAddrLowBits(DmaMemAddr addr, Bit#(TLog#(DMA_MEM_ADDR_WIDTH)) ptr);
    DmaMemAddr temp = 0;
    case(ptr)
        1 : temp = zeroExtend(DmaMemAddr'(addr[1 -1:0]));
        2 : temp = zeroExtend(DmaMemAddr'(addr[2 -1:0]));
        3 : temp = zeroExtend(DmaMemAddr'(addr[3 -1:0]));
        4 : temp = zeroExtend(DmaMemAddr'(addr[4 -1:0]));
        5 : temp = zeroExtend(DmaMemAddr'(addr[5 -1:0]));
        6 : temp = zeroExtend(DmaMemAddr'(addr[6 -1:0]));
        7 : temp = zeroExtend(DmaMemAddr'(addr[7 -1:0]));
        8 : temp = zeroExtend(DmaMemAddr'(addr[8 -1:0]));
        9 : temp = zeroExtend(DmaMemAddr'(addr[9 -1:0]));
        10: temp = zeroExtend(DmaMemAddr'(addr[10-1:0]));
        11: temp = zeroExtend(DmaMemAddr'(addr[11-1:0]));
        12: temp = zeroExtend(DmaMemAddr'(addr[12-1:0]));
        13: temp = zeroExtend(DmaMemAddr'(addr[13-1:0]));
        14: temp = zeroExtend(DmaMemAddr'(addr[14-1:0]));
        15: temp = zeroExtend(DmaMemAddr'(addr[15-1:0]));
        16: temp = zeroExtend(DmaMemAddr'(addr[16-1:0]));
        17: temp = zeroExtend(DmaMemAddr'(addr[17-1:0]));
        18: temp = zeroExtend(DmaMemAddr'(addr[18-1:0]));
        19: temp = zeroExtend(DmaMemAddr'(addr[19-1:0]));
        20: temp = zeroExtend(DmaMemAddr'(addr[20-1:0]));
        21: temp = zeroExtend(DmaMemAddr'(addr[21-1:0]));
        22: temp = zeroExtend(DmaMemAddr'(addr[22-1:0]));
        23: temp = zeroExtend(DmaMemAddr'(addr[23-1:0]));
        24: temp = zeroExtend(DmaMemAddr'(addr[24-1:0]));
        25: temp = zeroExtend(DmaMemAddr'(addr[25-1:0]));
        26: temp = zeroExtend(DmaMemAddr'(addr[26-1:0]));
        27: temp = zeroExtend(DmaMemAddr'(addr[27-1:0]));
        28: temp = zeroExtend(DmaMemAddr'(addr[28-1:0]));
        29: temp = zeroExtend(DmaMemAddr'(addr[29-1:0]));
        30: temp = zeroExtend(DmaMemAddr'(addr[30-1:0]));
        31: temp = zeroExtend(DmaMemAddr'(addr[31-1:0]));
        32: temp = zeroExtend(DmaMemAddr'(addr[32-1:0]));
        33: temp = zeroExtend(DmaMemAddr'(addr[33-1:0]));
        34: temp = zeroExtend(DmaMemAddr'(addr[34-1:0]));
        35: temp = zeroExtend(DmaMemAddr'(addr[35-1:0]));
        36: temp = zeroExtend(DmaMemAddr'(addr[36-1:0]));
        37: temp = zeroExtend(DmaMemAddr'(addr[37-1:0]));
        38: temp = zeroExtend(DmaMemAddr'(addr[38-1:0]));
        39: temp = zeroExtend(DmaMemAddr'(addr[39-1:0]));
        40: temp = zeroExtend(DmaMemAddr'(addr[40-1:0]));
        41: temp = zeroExtend(DmaMemAddr'(addr[41-1:0]));
        42: temp = zeroExtend(DmaMemAddr'(addr[42-1:0]));
        43: temp = zeroExtend(DmaMemAddr'(addr[43-1:0]));
        44: temp = zeroExtend(DmaMemAddr'(addr[44-1:0]));
        45: temp = zeroExtend(DmaMemAddr'(addr[45-1:0]));
        46: temp = zeroExtend(DmaMemAddr'(addr[46-1:0]));
        47: temp = zeroExtend(DmaMemAddr'(addr[47-1:0]));
        48: temp = zeroExtend(DmaMemAddr'(addr[48-1:0]));
        49: temp = zeroExtend(DmaMemAddr'(addr[49-1:0]));
        50: temp = zeroExtend(DmaMemAddr'(addr[50-1:0]));
        51: temp = zeroExtend(DmaMemAddr'(addr[51-1:0]));
        52: temp = zeroExtend(DmaMemAddr'(addr[52-1:0]));
        53: temp = zeroExtend(DmaMemAddr'(addr[53-1:0]));
        54: temp = zeroExtend(DmaMemAddr'(addr[54-1:0]));
        55: temp = zeroExtend(DmaMemAddr'(addr[55-1:0]));
        56: temp = zeroExtend(DmaMemAddr'(addr[56-1:0]));
        57: temp = zeroExtend(DmaMemAddr'(addr[57-1:0]));
        58: temp = zeroExtend(DmaMemAddr'(addr[58-1:0]));
        59: temp = zeroExtend(DmaMemAddr'(addr[59-1:0]));
        60: temp = zeroExtend(DmaMemAddr'(addr[60-1:0]));
        61: temp = zeroExtend(DmaMemAddr'(addr[61-1:0]));
        62: temp = zeroExtend(DmaMemAddr'(addr[62-1:0]));
        63: temp = zeroExtend(DmaMemAddr'(addr[63-1:0]));
        default: temp = 0;
    endcase
    return temp;
endfunction

typedef 32 CNTFIFO_SIZE_WIDTH;
typedef UInt#(CNTFIFO_SIZE_WIDTH) FifoSize;

interface CounteredFIFOF#(type t);
    method Action enq (t x);
    method Action deq;
    method t first;
    method Action clear;
    method Bool notFull;
    method Bool notEmpty;
    method FifoSize getCurSize;
endinterface

module mkCounteredFIFOF#(Integer depth)(CounteredFIFOF#(t)) provisos(Bits#(t, tSz));
    Wire#(Bool) hasDeqCall  <- mkDWire(False);
    Wire#(Bool) hasEnqCall  <- mkDWire(False);
    Reg#(FifoSize) curSize <- mkReg(0);
    FIFOF#(t) fifo <- mkSizedFIFOF(depth);

    rule updateSize;
        case({pack(hasEnqCall), pack(hasDeqCall)})
            2'b10:   curSize <= curSize + 1;
            2'b01:   curSize <= curSize -1;
            default: curSize <= curSize;
        endcase
    endrule

    method Action enq (t x);
        fifo.enq(x);
        hasEnqCall <= True;
    endmethod

    method Action deq;
        fifo.deq;
        hasDeqCall <= True;
    endmethod

    method t first = fifo.first;
    method Action clear  = fifo.clear;
    method Bool notFull  = fifo.notFull;
    method Bool notEmpty = fifo.notEmpty;

    method FifoSize getCurSize = curSize;
endmodule

function ByteParity calByteParity(Byte data);
    return (data[0] ^ data[1]  ^ data[2] ^ data[3] ^ data[4] ^ data[5] ^ data[6] ^ data[7]);
endfunction

typedef Bit#(BYTE_EN_WIDTH) DataParity;
typedef Bit#(TDiv#(DWORD_WIDTH, BYTE_WIDTH)) DwordParity;

function DataParity calDataParity(Data data);
    Vector#(BYTE_EN_WIDTH, Byte) dataBytes = unpack(data);
    Vector#(BYTE_EN_WIDTH, ByteParity) dataParities= newVector();
    for (Integer idx = 0; idx < valueOf(BYTE_EN_WIDTH); idx = idx + 1) begin
        dataParities[idx] = calByteParity(dataBytes[idx]);
    end
    return pack(dataParities);
endfunction
