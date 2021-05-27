Tools\srecord\srec_cat.exe ..\SRT-SNES\Binaries\SRTTest.sfc --binary --output TestROM64K.mif --mif 8
Tools\srecord\srec_cat.exe ..\SRT-SNES\Data\Placeholder2.bin --binary --output TestImage.mif --mif 8
Tools\srecord\srec_cat.exe ..\SRT-SNES\Data\PaletteMap.bin --binary --output PaletteMap.mif --mif 8
rem CommandBuffer.bin is a "dummy" empty command buffer used as a default
Tools\srecord\srec_cat.exe CommandBuffer.bin --binary --output CommandBuffer.mif --mif 64
