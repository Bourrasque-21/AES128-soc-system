set script_dir [file dirname [file normalize [info script]]]
set root_dir [file dirname $script_dir]

read_verilog -sv [list \
    [file join $root_dir rtl aes_pkg.sv] \
    [file join $root_dir rtl aes_sbox_bram_sync.sv] \
    [file join $root_dir rtl aes_shiftrows.sv] \
    [file join $root_dir rtl aes_mixcolumns.sv] \
    [file join $root_dir rtl gf128_mult_8bit_seq.sv] \
    [file join $root_dir rtl ghash_engine_seq.sv] \
    [file join $root_dir rtl aes128_full_pipeline_bram_core.sv] \
    [file join $root_dir rtl aes128_gcm_packet_context.sv] \
    [file join $root_dir rtl aes128_gcm_packet_pipeline_top.sv] \
]

synth_design -top aes128_gcm_packet_pipeline_top \
    -part xc7a35tcpg236-1 \
    -mode out_of_context \
    -flatten_hierarchy rebuilt

create_clock -period 10.000 -name clk [get_ports clk]

report_utilization -file [file join $root_dir report aes128_gcm_full_pipeline_synth_utilization.rpt]
report_timing_summary -file [file join $root_dir report aes128_gcm_full_pipeline_timing_summary.rpt]

puts "AES-128 GCM full-pipeline synthesis completed"
