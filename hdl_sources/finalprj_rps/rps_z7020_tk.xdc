#set_property -dict { PACKAGE_PIN M19   IOSTANDARD LVCMOS33 } [get_ports { CLK }];
#create_clock -add -name clk_pin -period 40.00 -waveform {0 20} [get_ports { CLK }];

#set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS33 } [get_ports { LED[7] }];
#set_property -dict { PACKAGE_PIN T17   IOSTANDARD LVCMOS33 } [get_ports { LED[6] }];
#set_property -dict { PACKAGE_PIN R19   IOSTANDARD LVCMOS33 } [get_ports { LED[5] }];
#set_property -dict { PACKAGE_PIN T19   IOSTANDARD LVCMOS33 } [get_ports { LED[4] }];
#set_property -dict { PACKAGE_PIN R18   IOSTANDARD LVCMOS33 } [get_ports { LED[3] }];
#set_property -dict { PACKAGE_PIN T18   IOSTANDARD LVCMOS33 } [get_ports { LED[2] }];
#set_property -dict { PACKAGE_PIN P16   IOSTANDARD LVCMOS33 } [get_ports { LED[1] }];
#set_property -dict { PACKAGE_PIN R16   IOSTANDARD LVCMOS33 } [get_ports { LED[0] }];
#set_property -dict { PACKAGE_PIN AA19   IOSTANDARD LVCMOS33 } [get_ports { PB[3] }]; #S4
#set_property -dict { PACKAGE_PIN Y19   IOSTANDARD LVCMOS33 } [get_ports { PB[2] }]; #S3
set_property -dict { PACKAGE_PIN AA18   IOSTANDARD LVCMOS33 } [get_ports { push_n }]; #S2
set_property -dict { PACKAGE_PIN Y18   IOSTANDARD LVCMOS33 } [get_ports { rst_n }]; #S1

#set_property -dict { PACKAGE_PIN Y20   IOSTANDARD LVCMOS33 } [get_ports { DIPSW[0] }];
#set_property -dict { PACKAGE_PIN Y21   IOSTANDARD LVCMOS33 } [get_ports { DIPSW[1] }];
#set_property -dict { PACKAGE_PIN AB19   IOSTANDARD LVCMOS33 } [get_ports { DIPSW[2] }];
#set_property -dict { PACKAGE_PIN AB20   IOSTANDARD LVCMOS33 } [get_ports { DIPSW[3] }];
#set_property -dict { PACKAGE_PIN AA22   IOSTANDARD LVCMOS33 } [get_ports { DIPSW[4] }];
#set_property -dict { PACKAGE_PIN AB22   IOSTANDARD LVCMOS33 } [get_ports { DIPSW[5] }];
#set_property -dict { PACKAGE_PIN AA21   IOSTANDARD LVCMOS33 } [get_ports { DIPSW[6] }];
#set_property -dict { PACKAGE_PIN AB21   IOSTANDARD LVCMOS33 } [get_ports { DIPSW[7] }];

#set_property -dict { PACKAGE_PIN Y6   IOSTANDARD LVCMOS33 } [get_ports { SEGOUT[7] }];
#set_property -dict { PACKAGE_PIN Y5   IOSTANDARD LVCMOS33 } [get_ports { SEGOUT[6] }];
#set_property -dict { PACKAGE_PIN AA7   IOSTANDARD LVCMOS33 } [get_ports { SEGOUT[5] }];
#set_property -dict { PACKAGE_PIN AA6   IOSTANDARD LVCMOS33 } [get_ports { SEGOUT[4] }];
#set_property -dict { PACKAGE_PIN AB2   IOSTANDARD LVCMOS33 } [get_ports { SEGOUT[3] }];
#set_property -dict { PACKAGE_PIN AB1   IOSTANDARD LVCMOS33 } [get_ports { SEGOUT[2] }];
#set_property -dict { PACKAGE_PIN AB5   IOSTANDARD LVCMOS33 } [get_ports { SEGOUT[1] }];
#set_property -dict { PACKAGE_PIN AB4   IOSTANDARD LVCMOS33 } [get_ports { SEGOUT[0] }];
#set_property -dict { PACKAGE_PIN AB7   IOSTANDARD LVCMOS33 } [get_ports { SEGCOM[7] }];
#set_property -dict { PACKAGE_PIN AB6   IOSTANDARD LVCMOS33 } [get_ports { SEGCOM[6] }];
#set_property -dict { PACKAGE_PIN Y4   IOSTANDARD LVCMOS33 } [get_ports { SEGCOM[5] }];
#set_property -dict { PACKAGE_PIN AA4   IOSTANDARD LVCMOS33 } [get_ports { SEGCOM[4] }];
#set_property -dict { PACKAGE_PIN R6   IOSTANDARD LVCMOS33 } [get_ports { SEGCOM[3] }];
#set_property -dict { PACKAGE_PIN T6   IOSTANDARD LVCMOS33 } [get_ports { SEGCOM[2] }];
#set_property -dict { PACKAGE_PIN T4   IOSTANDARD LVCMOS33 } [get_ports { SEGCOM[1] }];
#set_property -dict { PACKAGE_PIN U4   IOSTANDARD LVCMOS33 } [get_ports { SEGCOM[0] }];

#set_property -dict { PACKAGE_PIN F19   IOSTANDARD LVCMOS33 } [get_ports { LCD_RS }];
#set_property -dict { PACKAGE_PIN H20   IOSTANDARD LVCMOS33 } [get_ports { LCD_RW }];
#set_property -dict { PACKAGE_PIN G19   IOSTANDARD LVCMOS33 } [get_ports { LCD_EN }];
#set_property -dict { PACKAGE_PIN A22   IOSTANDARD LVCMOS33 } [get_ports { LCD_DATA[7] }];
#set_property -dict { PACKAGE_PIN D22   IOSTANDARD LVCMOS33 } [get_ports { LCD_DATA[6] }];
#set_property -dict { PACKAGE_PIN C22   IOSTANDARD LVCMOS33 } [get_ports { LCD_DATA[5] }];
#set_property -dict { PACKAGE_PIN E21   IOSTANDARD LVCMOS33 } [get_ports { LCD_DATA[4] }];
#set_property -dict { PACKAGE_PIN D21   IOSTANDARD LVCMOS33 } [get_ports { LCD_DATA[3] }];
#set_property -dict { PACKAGE_PIN B21   IOSTANDARD LVCMOS33 } [get_ports { LCD_DATA[2] }];
#set_property -dict { PACKAGE_PIN B22   IOSTANDARD LVCMOS33 } [get_ports { LCD_DATA[1] }];
#set_property -dict { PACKAGE_PIN H19   IOSTANDARD LVCMOS33 } [get_ports { LCD_DATA[0] }];

#set_property -dict { PACKAGE_PIN L17   IOSTANDARD LVCMOS33 } [get_ports { TFTLCD_TCLK }];
#set_property -dict { PACKAGE_PIN N17   IOSTANDARD LVCMOS33 } [get_ports { TFTLCD_Hsync }];
#set_property -dict { PACKAGE_PIN M17   IOSTANDARD LVCMOS33 } [get_ports { TFTLCD_Vsync }];
#set_property -dict { PACKAGE_PIN U22   IOSTANDARD LVCMOS33 } [get_ports { TFTLCD_DE_out }];
#set_property -dict { PACKAGE_PIN T22   IOSTANDARD LVCMOS33 } [get_ports { TFTLCD_R[7] }];
#set_property -dict { PACKAGE_PIN U21   IOSTANDARD LVCMOS33 } [get_ports { TFTLCD_R[6] }];
#set_property -dict { PACKAGE_PIN T21   IOSTANDARD LVCMOS33 } [get_ports { TFTLCD_R[5] }];
#set_property -dict { PACKAGE_PIN K20   IOSTANDARD LVCMOS33 } [get_ports { TFTLCD_R[4] }];
#set_property -dict { PACKAGE_PIN K19   IOSTANDARD LVCMOS33 } [get_ports { TFTLCD_R[3] }];
#set_property -dict { PACKAGE_PIN L22   IOSTANDARD LVCMOS33 } [get_ports { TFTLCD_G[7] }];
#set_property -dict { PACKAGE_PIN L21   IOSTANDARD LVCMOS33 } [get_ports { TFTLCD_G[6] }];
#set_property -dict { PACKAGE_PIN K21   IOSTANDARD LVCMOS33 } [get_ports { TFTLCD_G[5] }];
#set_property -dict { PACKAGE_PIN J20   IOSTANDARD LVCMOS33 } [get_ports { TFTLCD_G[4] }];
#set_property -dict { PACKAGE_PIN J22   IOSTANDARD LVCMOS33 } [get_ports { TFTLCD_G[3] }];
#set_property -dict { PACKAGE_PIN J21   IOSTANDARD LVCMOS33 } [get_ports { TFTLCD_G[2] }];
#set_property -dict { PACKAGE_PIN K18   IOSTANDARD LVCMOS33 } [get_ports { TFTLCD_B[7] }];
#set_property -dict { PACKAGE_PIN J18   IOSTANDARD LVCMOS33 } [get_ports { TFTLCD_B[6] }];
#set_property -dict { PACKAGE_PIN M16   IOSTANDARD LVCMOS33 } [get_ports { TFTLCD_B[5] }];
#set_property -dict { PACKAGE_PIN M15   IOSTANDARD LVCMOS33 } [get_ports { TFTLCD_B[4] }];
#set_property -dict { PACKAGE_PIN N18   IOSTANDARD LVCMOS33 } [get_ports { TFTLCD_B[3] }];
#set_property -dict { PACKAGE_PIN W22   IOSTANDARD LVCMOS33 } [get_ports { TFTLCD_Tpower }];
#set_property -dict { PACKAGE_PIN Y21   IOSTANDARD LVCMOS33 } [get_ports { TFTLCD_SW[1] }];
#set_property -dict { PACKAGE_PIN Y20   IOSTANDARD LVCMOS33 } [get_ports { TFTLCD_SW[0] }];

