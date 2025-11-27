import os
import shutil
import subprocess

from assassyn.frontend import *
from assassyn.backend import *
from assassyn import utils

from opcodes import *
from decoder import *
from execute import *
from bypass import *
from writeback import *
import sys as py_sys

class Execution(Module):
  def __init__(self):
    super().__init__("execution")

    self.add_submodule(Decoder())
    self.add_submodule(Execute())
    self.add_submodule(Bypass())
    self.add_submodule(WriteBack())

  def elaborate(self, platform):
    m = Module()

    m.submodules.decoder = self.submodules["decoder"]
    m.submodules.execute = self.submodules["execute"]
    m.submodules.bypass = self.submodules["bypass"]
    m.submodules.write_back = self.submodules["write_back"]

    return m
    
class Decoder(Module):
  def __init__(self):
    super().__init__("decoder")

    # Add decoder logic here

  def elaborate(self, platform):
    m = Module()

    # Implement decoder logic here

    return m
  
class Fetcher(Module):
  def __init__(self):
    super().__init__("fetcher")

    # Add fetcher logic here

  def elaborate(self, platform):
    m = Module()

    # Implement fetcher logic here

    return m
  
class FetchImpl(Downstream):
  def __init__(self):
    super().__init__("fetch_impl")

    self.add_submodule(Fetcher())

  def elaborate(self, platform):
    m = Module()

    m.submodules.fetcher = self.submodules["fetcher"]

    return m
  
class Onwrite(Downstream):
  def __init__(self):
    super().__init__("onwrite")

    self.add_submodule(WriteBack())

  def elaborate(self, platform):
    m = Module()

    m.submodules.write_back = self.submodules["write_back"]

    return m
  
class MemUser(Module):
  def __init__(self):
    super().__init__("mem_user")

    self.add_submodule(MemoryAccess())

  def elaborate(self, platform):
    m = Module()

    m.submodules.memory_access = self.submodules["memory_access"]

    return m
  
class Driver(Module):
  def __init__(self):
    super().__init__("driver")

    self.add_submodule(Execution())
    self.add_submodule(FetchImpl())
    self.add_submodule(Onwrite())
    self.add_submodule(MemUser())

  def elaborate(self, platform):
    m = Module()

    m.submodules.execution = self.submodules["execution"]
    m.submodules.fetch_impl = self.submodules["fetch_impl"]
    m.submodules.onwrite = self.submodules["onwrite"]
    m.submodules.mem_user = self.submodules["mem_user"]

    return m
  
def build_cpu(depth_log):
  cpu = Driver()
  utils.generate_verilog(cpu, "riscv_cpu", depth_log)

def run_cpu(sys, simulator_path, verilog_path, workload='default'):
  # Compile the simulator with the generated Verilog
  sim_executable = os.path.join(simulator_path, "simulator_exec")
  verilog_files = [os.path.join(verilog_path, f) for f in os.listdir(verilog_path) if f.endswith('.v')]
  
  compile_command = ["iverilog", "-o", sim_executable] + verilog_files
  subprocess.run(compile_command, check=True)

  # Run the simulator with the specified workload
  run_command = [sim_executable]
  if workload != 'default':
    run_command.append(workload)
  
  subprocess.run(run_command, check=True)

def check():
  # Placeholder for future checks
  pass

def cp_if_exists(src, dst, placeholder):
  if os.path.exists(src):
    shutil.copy(src, dst)
  else:
    with open(dst, 'w') as f:
      f.write(placeholder)

def init_workspace(base_path, case):
  workspace_path = os.path.join(base_path, "workspace", case)
  os.makedirs(workspace_path, exist_ok=True)

  cp_if_exists(
    os.path.join(base_path, "configs", case, "config.yaml"),
    os.path.join(workspace_path, "config.yaml"),
    "# Default config placeholder\n"
  )

  cp_if_exists(
    os.path.join(base_path, "configs", case, "workload.bin"),
    os.path.join(workspace_path, "workload.bin"),
    ""  # Empty placeholder for binary
  )

  return workspace_path

if __name__ == "__main__":
  base_path = py_sys.path[0]
  case = "default_case"
  workspace = init_workspace(base_path, case)

  verilog_output_path = os.path.join(workspace, "verilog")
  os.makedirs(verilog_output_path, exist_ok=True)

  build_cpu(depth_log=3)
  run_cpu(py_sys, simulator_path=workspace, verilog_path=verilog_output_path, workload=os.path.join(workspace, "workload.bin"))