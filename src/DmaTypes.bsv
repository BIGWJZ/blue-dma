import Vector::*;
import FShow::*;
import SemiFifo::*;
import PcieTypes::*;
import PcieAxiStreamTypes::*;
import PcieDescriptorTypes::*;

typedef PCIE_AXIS_DATA_WIDTH DATA_WIDTH;

typedef 64  DMA_MEM_ADDR_WIDTH;
typedef 32  DMA_REQ_LEN_WIDTH;

typedef 32 DMA_CSR_ADDR_WIDTH;
typedef 32 DMA_CSR_DATA_WIDTH;

typedef Bit#(DMA_MEM_ADDR_WIDTH) DmaMemAddr;
typedef Bit#(DMA_REQ_LEN_WIDTH)  DmaReqLen;
typedef Bit#(DMA_CSR_ADDR_WIDTH) DmaCsrAddr;
typedef Bit#(DMA_CSR_DATA_WIDTH) DmaCsrValue;

typedef TLog#(BYTE_WIDTH) BYTE_WIDTH_WIDTH;
typedef 2 BYTE_DWORD_SHIFT_WIDTH;

typedef Bit#(BYTE_WIDTH) Byte;
typedef Bit#(DWORD_WIDTH) DWord;
typedef Bit#(1) ByteParity;

typedef 4096                                BUS_BOUNDARY;
typedef TAdd#(1, TLog#(BUS_BOUNDARY))       BUS_BOUNDARY_WIDTH;

typedef 128                                 DEFAULT_TLP_SIZE;
typedef TLog#(DEFAULT_TLP_SIZE)             DEFAULT_TLP_SIZE_WIDTH;
// Only support max to 512bytes TLP for resouce saving
typedef 512                                 MAX_TLP_SIZE;
typedef TLog#(MAX_TLP_SIZE)                 MAX_TLP_SIZE_WIDTH;
typedef Bit#(BUS_BOUNDARY_WIDTH)            TlpPayloadSize;
typedef Bit#(TLog#(BUS_BOUNDARY_WIDTH))     TlpPayloadSizeWidth;

typedef struct {
    TlpPayloadSize      mps;
    TlpPayloadSizeWidth mpsWidth;
    TlpPayloadSize      mrrs;
    TlpPayloadSizeWidth mrrsWidth;
} TlpSizeCfg deriving(Bits, Eq, Bounded, FShow);

typedef 2 CONCAT_STREAM_NUM;

typedef TDiv#(DATA_WIDTH, BYTE_WIDTH)  BYTE_EN_WIDTH;
typedef TDiv#(DATA_WIDTH, DWORD_WIDTH) DWORD_EN_WIDTH;

typedef Bit#(DATA_WIDTH) Data;
typedef Bit#(BYTE_EN_WIDTH) ByteEn;
typedef Bit#(DWORD_BYTES) DWordByteEn;

typedef Bit#(TAdd#(1, TLog#(DATA_WIDTH)))     DataBitPtr;
typedef Bit#(TAdd#(1, TLog#(BYTE_EN_WIDTH)))  DataBytePtr;
typedef Bit#(TAdd#(1, TLog#(DWORD_EN_WIDTH))) DataDwordPtr;

typedef Bit#(TAdd#(1, TLog#(DWORD_BYTES)))    DWordBytePtr;
typedef Bit#(BYTE_DWORD_SHIFT_WIDTH)          ByteModDWord;
typedef 2'b11                                 MaxByteModDword;

typedef TSub#(BUS_BOUNDARY_WIDTH, MAX_TLP_SIZE_WIDTH) READ_REQ_CNT_WIDTH;
typedef Bit#(READ_REQ_CNT_WIDTH)              DmaReadReqCnt;

typedef struct {
    DmaMemAddr startAddr;
    DmaReqLen  length;
    Bool       isWrite;
} DmaRequest deriving(Bits, Bounded, Eq);

typedef struct {
    DmaMemAddr startAddr;
    DmaMemAddr endAddr;
    DmaReqLen  length;
    Tag        tag;
} DmaExtendRequest deriving(Bits, Bounded, Eq);

typedef struct {
    DmaCsrAddr  addr;
    DmaCsrValue value;
    Bool        isWrite;
} CsrRequest deriving(Bits, Bounded, Eq);

typedef struct {
    DmaCsrAddr  addr;
    DmaCsrValue value;
} CsrResponse deriving(Bits, Bounded, Eq);

typedef enum {
    DMA_RX, 
    DMA_TX
} TRXDirection deriving(Bits, Eq, FShow);

typedef struct {
    Data data;
    ByteEn byteEn;
    Bool isFirst;
    Bool isLast;
} DataStream deriving(Bits, Bounded, Eq);

typedef Tuple2#(
    DWordByteEn,
    DWordByteEn
) SideBandByteEn;

instance FShow#(DmaRequest);
    function Fmt fshow(DmaRequest request);
        return ($format("<DmaRequest: startAddr=%h, length=%h, isWrite=%b", request.startAddr, request.length, pack(request.isWrite)));
    endfunction
endinstance

instance FShow#(DataStream);
    function Fmt fshow(DataStream stream);
        return ($format("<DataStream      \n",
            "     data    = %h\n", stream.data, 
            "     byteEn  = %b\n", stream.byteEn,
            "     isFirst = %b", pack(stream.isFirst), ", isLast = %b", pack(stream.isLast)
        ));
    endfunction
endinstance

// Bdma User 

typedef struct {
    DmaMemAddr addr;
    DmaReqLen  len;
} BdmaUserC2hRdReq deriving(Bits, FShow);

typedef struct {
    DataStream dataStream;
} BdmaUserC2hRdResp deriving(Bits, FShow);

typedef struct {
    DmaMemAddr addr;
    DmaReqLen  len;
    DataStream dataStream;
} BdmaUserC2hWrReq deriving(Bits, FShow);

typedef struct {
} BdmaUserC2hWrResp deriving(Bits, FShow);

typedef struct {
    Bit#(sz_csr_addr) addr;
    Bit#(sz_csr_data) data;
} BdmaUserH2cWrReq#(numeric type sz_csr_addr, numeric type sz_csr_data) deriving(Bits, FShow);

typedef struct {
} BdmaUserH2cWrResp deriving(Bits, FShow);

typedef struct {
    Bit#(sz_csr_addr) addr;
} BdmaUserH2cRdReq#(numeric type sz_csr_addr) deriving(Bits, FShow);

typedef struct {
    Bit#(sz_csr_data) data;
} BdmaUserH2cRdResp#(numeric type sz_csr_data) deriving(Bits, FShow);

// Straddle Parameters

typedef TDiv#(DATA_WIDTH, PCIE_STRADDLE_NUM) STRADDLE_THRESH_BIT_WIDTH;
typedef TDiv#(BYTE_EN_WIDTH, PCIE_STRADDLE_NUM) STRADDLE_THRESH_BYTE_WIDTH;
typedef TDiv#(DWORD_EN_WIDTH, PCIE_STRADDLE_NUM) STRADDLE_THRESH_DWORD_WIDTH;

typedef struct {
    Data     data;
    ByteEn   byteEn;
    Bool     isDoubleFrame;
    Vector#(PCIE_STRADDLE_NUM, Bool) isFirst;
    Vector#(PCIE_STRADDLE_NUM, Bool) isLast;
    Vector#(PCIE_STRADDLE_NUM, SlotToken)  tag;
    Vector#(PCIE_STRADDLE_NUM, Bool) isCompleted;
} StraddleStream deriving(Bits, Bounded, Eq);

instance FShow#(StraddleStream);
    function Fmt fshow(StraddleStream stream);
        return ($format("<StraddleStream      \n",
            "     data    = %h\n", stream.data, 
            "     byteEn  = %b\n", stream.byteEn,
            "     isDoubleFrame = %b\n", stream.isDoubleFrame,
            "     isFirst = %b", pack(stream.isFirst[0]), ", isLast = %b\n", pack(stream.isLast[0]),
            "     isFirst = %b", pack(stream.isFirst[1]), ", isLast = %b\n", pack(stream.isLast[1])
        ));
    endfunction
endinstance

function StraddleStream getEmptyStraddleStream();
    let sdStream = StraddleStream {
        data      : 0,
        byteEn    : 0,
        isDoubleFrame : False,
        isFirst   : replicate(False),
        isLast    : replicate(False),
        tag       : replicate(0),
        isCompleted : replicate(False)
    };
    return sdStream;
endfunction

function Data getStraddleData(PcieTlpCtlIsSopPtr isSopPtr, Data data);
    Data sData = 0;
    if (isSopPtr == fromInteger(valueOf(ISSOP_LANE_0))) begin
        sData = zeroExtend(Data'(data[valueOf(STRADDLE_THRESH_BIT_WIDTH)-1:0]));
    end
    else begin
        sData = data >> valueOf(STRADDLE_THRESH_BIT_WIDTH);
    end
    return sData;
endfunction

function ByteEn getStraddleByteEn(PcieTlpCtlIsSopPtr isSopPtr, ByteEn byteEn);
    ByteEn sByteEn = 0;
    if (isSopPtr == fromInteger(valueOf(ISSOP_LANE_0))) begin
        sByteEn = zeroExtend(ByteEn'(byteEn[valueOf(STRADDLE_THRESH_BYTE_WIDTH)-1:0]));
    end
    else begin
        sByteEn = byteEn >> valueOf(STRADDLE_THRESH_BYTE_WIDTH);
    end
    return sByteEn;
endfunction

typedef 2 DMA_PATH_NUM;

typedef TAdd#(1, TLog#(DMA_PATH_NUM)) DMA_PATH_WIDTH;
typedef Bit#(DMA_PATH_WIDTH) DmaPathNo;

typedef TAdd#(1, TLog#(PCIE_STRADDLE_NUM)) PCIE_STRADDLE_WIDTH;
typedef Bit#(PCIE_STRADDLE_WIDTH) StraddleNo;

// Reorder types
typedef TSub#(DES_NONEXTENDED_TAG_WIDTH, 1) SLOT_TOKEN_WIDTH;
typedef Bit#(SLOT_TOKEN_WIDTH) SlotToken;
typedef 16 SLOT_PER_PATH;
typedef TAdd#(1, TDiv#(MAX_TLP_SIZE, BYTE_EN_WIDTH)) MAX_STREAM_NUM_PER_COMPLETION;

// Internal Registers 
/* Block 1 - DMA inner Ctrl Regs
 * Block 2 - Addr Table Lo Addr Path0
 * Block 3 - Addr Table Hi Addr Path0
 * Block 4 - Addr Table Lo Addr Path1
 * Block 5 - Addr Table Hi Addr Path1
 * Block 6 ~ 7 - Reserved Or External Modules Use
 * 4K Boundary
 * Block 8 ~ N - External Modules Use 
 */
typedef 512 DMA_INTERNAL_REG_BLOCK;
typedef TLog#(DMA_INTERNAL_REG_BLOCK) DMA_INTERNAL_REG_BLOCK_WIDTH;

typedef 16 DMA_INTERNAL_REG_BLOCK_NUM;
typedef Bit#(TLog#(DMA_INTERNAL_REG_BLOCK_NUM)) DmaRegBlockIdx;

typedef TMul#(DMA_INTERNAL_REG_BLOCK, 1) DMA_PA_TABLE0_OFFSET;
typedef TMul#(DMA_INTERNAL_REG_BLOCK, 3) DMA_PA_TABLE1_OFFSET;

// Control Reg offset of Block 0
typedef Bit#(TLog#(DMA_INTERNAL_REG_BLOCK)) DmaRegIndex;
typedef 16  DMA_USING_REG_LEN;

// Engine's Registers
typedef 1  REG_REQ_VA_LO_OFFSET;     // DmaRequest.startAddr
typedef 2  REG_REQ_VA_HI_OFFSET;
typedef 3  REG_REQ_BYTES_OFFSET;     // DmaRequest.length
typedef 4  REG_RESULT_VA_LO_OFFSET;  // Done flag write back address
typedef 5  REG_RESULT_VA_HI_OFFSET;

typedef 0  REG_ENGINE_0_OFFSET;      // Doorbell, indicates
typedef 6  REG_ENGINE_1_OFFSET;

// VA-PA Table, allow 512 VA-PA Page Elements, i.e. 2M(4K page, default) or 1G(2M huge page, recommend configuration)
typedef DMA_INTERNAL_REG_BLOCK PA_NUM;
typedef TMul#(PA_NUM, 2) DMA_PHY_ADDR_REG_LEN;

typedef Bit#(TLog#(PA_NUM)) PaBramAddr;
typedef 2 PA_TABLE0_BLOCK_OFFSET;
typedef 4 PA_TABLE1_BLOCK_OFFSET;

typedef 0 IS_HUGE_PAGE;

typedef 4096 PAGE_SIZE;
typedef TLog#(PAGE_SIZE) PAGE_SIZE_WIDTH;

typedef 'h200000 HUGE_PAGE_SIZE;
typedef TLog#(HUGE_PAGE_SIZE) HUGE_PAGE_SIZE_WIDTH;





