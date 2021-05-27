# Here be dragons. So many, many dragons.
# Timing constraints are all over the place generally, and woefully inadequately specified.

set_time_format -unit ns -decimal_places 3

create_clock -name clock -period "50MHz" [get_ports { clock }]
create_clock -name "i2c_20k_clock" -period 50000.000ns [get_keepers *mI2C_CTRL_CLK]

derive_pll_clocks
derive_clock_uncertainty

set_false_path -from * -to [get_ports { led[*] }]
set_false_path -from [get_ports { switchR switchG switchB key0_n key1_n reset_n }] -to *

set_output_delay -clock { clock } -add_delay 1 [get_ports { led[*] }]

set_input_delay -clock { clock } -add_delay 1 [get_ports { cartAddressBus[*] cartCS_n cartOE_n }]
set_output_delay -clock { clock } -add_delay 1 [get_ports { cartDataBus[*] cartDataBusOE_n }]

set_input_delay -clock { clock } -add_delay 1 [get_ports { HDMI_TX_INT HDMI_I2C_SDA }]
set_output_delay -clock { clock } -add_delay 1 [get_ports { HDMI_I2S0 HDMI_MCLK HDMI_LRCLK HDMI_SCLK HDMI_TX_D[*] HDMI_TX_VS HDMI_TX_HS HDMI_TX_DE HDMI_TX_CLK HDMI_I2C_SCL HDMI_I2C_SDA }]

# Ray direction calculation

set_multicycle_path -from [get_registers { *currentRayDir* } ] -to [get_registers { *rayDirX* *rayDirY* *rayDirZ* *primaryRayDir* }] -setup -end 5

# Ray colour calculation

set_multicycle_path -from [get_registers { *primaryRayDir* } ] -to [get_registers { *primaryRayColour* *secondaryRayColour* }] -setup -end 2
set_multicycle_path -from [get_registers { *PrimaryHitNormal* *SecondaryHitNormal* } ] -to [get_registers { *primaryRayColour* *secondaryRayColour* }] -setup -end 5

# Fudge timing for the SNES bus signals because our clock really isn't so important

set_multicycle_path -from [get_keepers { *SNESInterface* } ] -to [get_keepers { cartDataBus* }] -setup -end 2
set_multicycle_path -from [get_registers { *SNESInterface* } ] -to [get_keepers { cartDataBus* }] -setup -end 2
