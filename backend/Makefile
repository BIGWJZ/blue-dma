include ../Makefile.base

TCLDIR ?= xdc
CLK ?= rdma_clock
OOC ?= 1
VLOGDIR ?= verilog
OUTPUTDIR ?= output
LOGFILE ?= run_vivado.log
RUNTOPHASE ?= synth # synth place route all
# vu13p, u200
TARGETPLATFORM ?= u200
# xcvu13p-fhgb2104-2-i, xcu200-fsgd2104-2-e
PARTNAME = xcu200-fsgd2104-2-e
TARGETFILE ?= ../src/DmaWrapper.bsv
#MODULE List: mkRawSimpleDmaController mkRawBypassDmaController mkRawTestDmaController
TOPMODULE ?= mkRawTestDmaController

BACKENDDIR ?= .

VERILOG_TOPMODULE ?= top
MAX_NET_PATH_NUM ?= 100000

export DIR_RTL = $(VLOGDIR)
export DIR_BOARD = $(TARGETPLATFORM)
export DIR_XDC = $(TARGETPLATFORM)/$(TCLDIR)
export DIR_OOC_SCRIPTS = $(BACKENDDIR)/ooc_tcl_and_xdc
export DIR_IPS = $(BACKENDDIR)/ips
export DIR_IP_GENERATED = $(BUILDDIR)/ips
export DIR_BSV_GENERATED = $(BACKENDDIR)/verilog
export VERILOG_TOPMODULE
export TARGET_CLOCKS = $(CLK)
export DIR_OUTPUT = $(OUTPUTDIR)
export OOCSYNTH = $(OOC)
export RUNTO = $(RUNTOPHASE)
export PART = $(PARTNAME)
export MAX_NET_PATH_NUM

compile:
	mkdir -p $(BUILDDIR)
	bsc -elab -sim -verbose $(BLUESIMFLAGS) $(DEBUGFLAGS) $(DIRFLAGS) $(MISCFLAGS) $(RECOMPILEFLAGS) $(RUNTIMEFLAGS) $(SCHEDFLAGS) $(TRANSFLAGS) -g $(TOPMODULE) $(TARGETFILE)

verilog: compile
	mkdir -p $(VLOGDIR)
	bsc $(VERILOGFLAGS) $(DIRFLAGS) $(MISCFLAGS) $(RECOMPILEFLAGS) $(RUNTIMEFLAGS) $(TRANSFLAGS) -g $(TOPMODULE) $(TARGETFILE)
	bluetcl listVlogFiles.tcl -bdir $(BUILDDIR) -vdir $(BUILDDIR) $(TOPMODULE) $(TOPMODULE) | grep -i '\.v' | xargs -I {} cp {} $(VLOGDIR)

vivado: 
	vivado -mode tcl -nolog -nojournal -source ./build_top.tcl 2>&1 | tee $(LOGFILE)

vivado_synth:
	vivado -mode tcl -nolog -nojournal -source ./build_top.tcl -tclargs synth 2>&1 | tee $(LOGFILE)

vivado_prw:
	vivado -mode tcl -nolog -nojournal -source ./build_top.tcl -tclargs prw 2>&1 | tee $(LOGFILE)

clean:
	rm -rf $(BUILDDIR) $(OUTPUTDIR) $(VLOGDIR) .Xil *.jou *.log

.PHONY: verilog vivado clean
.DEFAULT_GOAL := verilog