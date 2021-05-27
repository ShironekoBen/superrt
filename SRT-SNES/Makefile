.DEFAULT_GOAL := build

# Directories
SOURCEDIR = Source
BUILDDIR = Build
BINDIR = Binaries

# Tools
EMU = "../../SNES/bsnes-plus-05-x64/bsnes.exe"

# ROM setup
name		:= SRTTest
debug		:= 1

# libSFX paths
rom	    := $(BINDIR)/$(name).sfc
obj_dir := $(BUILDDIR)

# Source files
src			:= $(SOURCEDIR)/SRTTest.s # $(call rwildcard, ,$(SOURCEDIR)/%.s)
src_smp		:= #$(call rwildcard, ,$(SOURCEDIR)/%.s700)
src_gsu		:= #$(call rwildcard, ,$(SOURCEDIR)/%.sgs)
headers		:= #$(call rwildcard, ,$(SOURCEDIR)/%.i) $(call rwildcard, ,$(SOURCEDIR)/%.i700)

# Derived data files
derived_files	:=

# Include libSFX.make
libsfx_dir	:= External/libSFX
include $(libsfx_dir)/libSFX.make

build: $(TARGET)

#run: $(TARGET)
#		$(EMU) $(rom)
