$b = 'C:\intelFPGA_lite\20.1\modelsim_ase\win32aloem'
python tools/asm.py tests/selftest.s tests/selftest.hex
python tools/asm.py tests/demo.s program.hex
if (-not (Test-Path sim/work)) { & "$b\vlib.exe" sim/work | Out-Null }
& "$b\vlog.exe" -work sim/work -sv alu.sv pc.sv inc_alu.sv branch_alu.sv ins_mem.sv ext_sram_ctrl.sv data_mem.sv regfile.sv imm_gen.sv control.sv cpu.sv tests/tb_cpu.sv
& "$b\vsim.exe" -c -lib sim/work tb_cpu -do "run -all; quit" | Select-String "PASS|FAIL|Error"
