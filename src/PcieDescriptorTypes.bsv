
import PcieAxiStreamTypes::*;

typedef 64 RQ_DESCRIPTOR_WIDTH;
typedef TDiv#(TSub#(PCIE_AXIS_DATA_WIDTH, RQ_DESCRIPTOR_WIDTH), DWORD_WIDTH) MAX_DWORD_CNT_OF_FIRST;

typedef Bit#(1) ReserveBit1;
typedef Bit#(2) ReserveBit2;
typedef Bit#(6) ReserveBit6;

typedef 128 DES_CQ_DESCRIPTOR_WIDTH;
typedef 3  DES_ATTR_WIDTH; 
typedef 3  DES_TC_WIDTH;
typedef 6  DES_BAR_APERTURE_WIDTH;
typedef 3  DES_BAR_ID_WIDTH;
typedef 8  DES_TARGET_FUNCTION_WIDTH;
typedef 8  DES_TAG_WIDTH;
typedef 5  DES_NONEXTENDED_TAG_WIDTH;
typedef 16 DES_BDF_WIDTH;
typedef 4  DES_REQ_TYPE_WIDTH;
typedef 11 DES_DWORD_COUNT_WIDTH;
typedef 62 DES_ADDR_WIDTH;
typedef 2  DES_ADDR_TYPE_WIDTH;

typedef Bit#(DES_ATTR_WIDTH)            Attributes;
typedef Bit#(DES_TC_WIDTH)              TrafficClass;
typedef Bit#(DES_BAR_APERTURE_WIDTH)    BarAperture;
typedef Bit#(DES_BAR_ID_WIDTH)          BarId;
typedef Bit#(DES_TARGET_FUNCTION_WIDTH) TargetFunction;
typedef Bit#(DES_TAG_WIDTH)             Tag;
typedef Bit#(DES_BDF_WIDTH)             BusDeviceFunc;
typedef Bit#(DES_REQ_TYPE_WIDTH)        ReqType;
typedef Bit#(DES_DWORD_COUNT_WIDTH)     DwordCount;
typedef Bit#(DES_ADDR_WIDTH)            Address;
typedef Bit#(DES_ADDR_TYPE_WIDTH)       AddrType;

typedef 3'b001 ATTR_NO_SNOOP;

// 16bytes Completer Request Descriptor Format for Memory, I/O, and Atomic Options
typedef struct {
    // DW + 3
    ReserveBit1     reserve0;
    Attributes      attributes;
    TrafficClass    trafficClass;
    BarAperture     barAperture;
    BarId           barId;
    TargetFunction  targetFunction;
    Tag             tag;
    // DW + 2
    BusDeviceFunc   requesterId;
    ReserveBit1     reserve1;
    ReqType         reqType;
    DwordCount      dwordCnt;
    // DW + 1 & DW + 0
    Address         address;    
    AddrType        addrType;
} PcieCompleterRequestDescriptor deriving(Bits, Eq, Bounded, FShow);

typedef 96 DES_CC_DESCRIPTOR_WIDTH;
typedef 3  DES_CMPL_STATUS_WIDTH;
typedef 13 DES_CMPL_BYTE_CNT_WIDTH;
typedef 7  DES_CC_LOWER_ADDR_WIDTH;
typedef Bit#(DES_CMPL_STATUS_WIDTH)   CmplStatus;
typedef Bit#(DES_CMPL_BYTE_CNT_WIDTH) CmplByteCnt;
typedef Bit#(DES_CC_LOWER_ADDR_WIDTH) CCLowerAddr;

typedef 0 DES_CC_STAUS_SUCCESS;
typedef 1 DES_CC_STATUS_UPSUPPORT;
typedef 4 DES_CC_STATUS_ABORT; 

typedef struct {
    // DW + 2
    ReserveBit1     reserve0;
    Attributes      attributes;
    TrafficClass    trafficClass;
    Bool            completerIdEn;
    BusDeviceFunc   completerId;
    Tag             tag;
    // DW + 1
    BusDeviceFunc   requesterId;
    ReserveBit1     reserve1;
    Bool            isPoisoned;
    CmplStatus      status;
    DwordCount      dwordCnt;
    // DW + 0
    ReserveBit2     reserve2;
    Bool            isLockedReadCmpl;
    CmplByteCnt     byteCnt;
    ReserveBit6     reserve3;
    AddrType        addrType;
    ReserveBit1     reserve4;
    CCLowerAddr     lowerAddr;
} PcieCompleterCompleteDescriptor deriving(Bits, Eq, Bounded, FShow);

typedef 128 DES_RQ_DESCRIPTOR_WIDTH;

typedef struct {
    // DW + 3
    Bool            forceECRC;
    Attributes      attributes;
    TrafficClass    trafficClass;
    Bool            requesterIdEn;
    BusDeviceFunc   completerId;
    Tag             tag;
    // DW + 2
    BusDeviceFunc   requesterId;
    Bool            isPoisoned;
    ReqType         reqType;
    DwordCount      dwordCnt;
    // DW + 1 & DW + 0
    Address         address;
    AddrType        addrType;
} PcieRequesterRequestDescriptor deriving(Bits, Eq, Bounded, FShow);

typedef 96 DES_RC_DESCRIPTOR_WIDTH;
typedef 4  DES_ERROR_CODE_WIDTH;
typedef 12 DES_RC_LOWER_ADDR_WIDTH;

typedef Bit#(DES_ERROR_CODE_WIDTH)    ErrorCode;
typedef Bit#(DES_RC_LOWER_ADDR_WIDTH) RCLowerAddr;

typedef struct {
    // DW + 2
    ReserveBit1     reserve0;
    Attributes      attributes;
    TrafficClass    trafficClass;
    ReserveBit1     reserve1;
    BusDeviceFunc   completerId;
    Tag             tag;
    // DW + 1
    BusDeviceFunc   requesterId;
    ReserveBit1     reserve2;
    Bool            isPoisoned;
    CmplStatus      status;
    DwordCount      dwordCnt;
    ReserveBit1     reserve3;
    Bool            isRequestCompleted;
    Bool            isLockedReadCmpl;
    CmplByteCnt     byteCnt;
    ErrorCode       errorcode;
    RCLowerAddr     lowerAddr;
} PcieRequesterCompleteDescriptor deriving(Bits, Eq, Bounded, FShow);

// Pcie Tlp types of descriptor
typedef 4'b0000 MEM_READ_REQ;
typedef 4'b0001 MEM_WRITE_REQ;
typedef 4'b0010 IO_READ_REQ;
typedef 4'b0011 IO_WRITE_REQ;
typedef 4'b0100 MEM_FETCHADD_REQ;
typedef 4'b0101 MEM_UNCOND_SWAP_REQ;
typedef 4'b0110 MEM_COMP_SWAP_REQ;
typedef 4'b0111 LOCK_READ_REQ; // allowed only in legacy devices
typedef 4'b1100 COMMON_MESG;
typedef 4'b1101 VENDOR_DEF_MESG;
typedef 4'b1110 ATS_MESG;

// Pcie Addr Types
typedef 2'b00 UNTRANSLATED_ADDR;
typedef 2'b01 TRANSLATION_REQ;
typedef 2'b10 TRANSLATED_ADDR;

//Cmpl Status
typedef 3'b000 SUCCESSFUL_CMPL;
typedef 3'b001 UNSUPPORTED_REQ;
typedef 3'b010 CFG_REQ_RETRY_STATUS;
typedef 3'b100 COMPLETER_ABORT;
