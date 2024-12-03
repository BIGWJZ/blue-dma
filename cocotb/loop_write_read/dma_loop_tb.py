import os
import random

import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock

import cocotb_test.simulator

import sys
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from bdmatb import BdmaLoopTb

tests_dir = os.path.dirname(__file__)
rtl_dir = tests_dir

async def loop_write_read_once(pcie_tb, mem):
    # addr, length = pcie_tb.gen_random_req(0)
    addr = 1
    length = 2378
    addr = mem.get_absolute_address(addr)
    char = bytes(random.choice('abcdefghijklmnopqrstuvwxyz'), encoding="UTF-8")
    data = char * length
    mem[addr:addr+length] = data
    await pcie_tb.run_single_read_once(0, addr, length)
    new_addr = addr + 8192
    await pcie_tb.run_single_write_once(0, new_addr, length)
    await Timer(200+4*length, units='ns')
    assert mem[new_addr:new_addr+length] == data

@cocotb.test(timeout_time=10000000, timeout_unit="ns")   
async def bar_test(dut):
    tb = BdmaLoopTb(dut)
    await tb.gen_reset()
    
    await tb.rc.enumerate()
    dev = tb.rc.find_device(tb.dev.functions[0].pcie_id)
    
    await dev.enable_device()
    await dev.set_master()
    
    dev_bar0 = dev.bar_window[0]
    tb.conbine_bar(dev_bar0)
    await tb.memory_map()
    
    mem = tb.rc.mem_pool.alloc_region(1024*1024)
    await loop_write_read_once(tb, mem)
    
def test_dma():
    dut = "mkRawTestDmaController"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = [
        os.path.join(rtl_dir, f"{dut}.v")
    ]

    sim_build = os.path.join(tests_dir, "sim_build", dut)

    cocotb_test.simulator.run(
        python_search=[tests_dir],
        verilog_sources=verilog_sources,
        toplevel=toplevel,
        module=module,
        timescale="1ns/1ps",
        sim_build=sim_build
    )
    
if __name__ == "__main__":
    test_dma()