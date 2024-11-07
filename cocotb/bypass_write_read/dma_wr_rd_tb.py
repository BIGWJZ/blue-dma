#!/usr/bin/env python
import logging
import os
import random

import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock

import cocotb_test.simulator

import sys
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from bdmatb import BdmaBypassTb

#  class TB architecture
#  --------------        -------------         ----------- 
# | Root Complex | <->  | End Pointer |  <->  | Dut(DMAC) |         
#  --------------        -------------         -----------
test_num = 100

async def single_path_random_write_test(pcie_tb, dma_channel, mem):
    for _ in range(test_num):
        addr, length = pcie_tb.gen_random_req(dma_channel)
        addr = mem.get_absolute_address(addr)
        char = bytes(random.choice('abcdefghijklmnopqrstuvwxyz'), encoding="UTF-8")
        data = char * length
        await pcie_tb.run_single_write_once(dma_channel, addr, data)
        await Timer(100+length, units='ns')
        assert mem[addr:addr+length] == data
            

async def single_path_random_read_test(pcie_tb, dma_channel, mem):
    for _ in range(test_num):
        addr, length = pcie_tb.gen_random_req(dma_channel)
        addr = mem.get_absolute_address(addr)
        char = bytes(random.choice('abcdefghijklmnopqrstuvwxyz'), encoding="UTF-8")
        mem[addr:addr+length] = char * length
        data = await pcie_tb.run_single_read_once(dma_channel, addr, length)
        assert data == char * length
            
@cocotb.test(timeout_time=100000000, timeout_unit="ns")
async def step_random_write_test(dut):

    tb = BdmaBypassTb(dut)
    await tb.gen_reset()
    
    await tb.rc.enumerate()
    dev = tb.rc.find_device(tb.dev.functions[0].pcie_id)
    
    await dev.enable_device()
    await dev.set_master()
    
    mem = tb.rc.mem_pool.alloc_region(1024*1024)
    
    await single_path_random_write_test(tb, 0, mem)
    
@cocotb.test(timeout_time=10000000, timeout_unit="ns")   
async def step_random_read_test(dut):
    tb = BdmaBypassTb(dut)
    await tb.gen_reset()
    
    await tb.rc.enumerate()
    dev = tb.rc.find_device(tb.dev.functions[0].pcie_id)
    
    await dev.enable_device()
    await dev.set_master()
    
    mem = tb.rc.mem_pool.alloc_region(1024*1024)
    
    await single_path_random_read_test(tb, 0, mem)

tests_dir = os.path.dirname(__file__)
rtl_dir = tests_dir
bdmatb_dir = os.path.dirname(tests_dir)


def test_dma():
    dut = "mkRawBypassDmaController"
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