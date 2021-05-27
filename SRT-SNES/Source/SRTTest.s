; SuperRT testbed
; By Ben Carter (c) 2021 Shironeko Labs

.include "libSFX.i"
.feature org_per_seg

; The start/end of our display region (outside this we force blanking to get extra DMA time)
SCREEN_DISPLAY_START_LINE = 32 - 1
SCREEN_DISPLAY_END_LINE = 192 - 1

; How fast to move the camera (in terms of a right-shift factor, so +1 halves speed)
CAMERA_MOVE_SPEED_SHIFT = 3

; Edit point data for the command list
.include "Data/CommandEditPoints.s"

; Clear the high byte of the accumulator
.macro ClearHighByteOfA
	RW_push set:a16i16
	and #$FF
	RW_pull
.endmac

; Set a new print location from X and Y
; Corrupts A
.macro SetPrintLoc new_x, new_y
	RW_push set:a8i16
	lda #new_x
	sta PrintX
	lda #new_y
	sta PrintY
	RW_pull
.endmac

; Set a new print location from X and Y, pushing the old one to the stack
; Corrupts A
.macro PushPrintLoc new_x, new_y
	RW_push set:a8i16
	lda PrintX
	pha
	lda PrintY
	pha
	lda #new_x
	sta PrintX
	lda #new_y
	sta PrintY
	RW_pull
.endmac

; Pop a stored print location from the stack
; Corrupts A
.macro PopPrintLoc
	pla
	sta PrintY
	pla
	sta PrintX
.endmac

; VBlank handler
proc VblankInterruptHandler, a8i16
	
	RW_push set:a16i16
	; Store registers

	pha
	php
	phx
	phy

	RW a8i16
	inc FPSFrameCount

	; Update tick counter
	lda WantNewTick
	cmp #0
	bne :+ ; Don't increment if there is still a pending tick outstanding (which can happen if the SRT update and tick collided so that the latter was deferred)
	inc TickVSyncCount
	lda TickVSyncCount
	cmp #2
	bne :+
	stz TickVSyncCount
	lda #1
	sta WantNewTick
:
	RW a16i16

	ply
	plx
	plp
	pla

	RW_pull
	rtl
endproc

; HBlank handler
proc HblankInterruptHandler, a8i16
	RW_push set:a16i16
	; Store registers

	pha
	php
	phx
	phy

	; Empirically we get here about 2/3 of the way through the scanline (TBH, I'm not sure /why/ - looks like it
	; may be immediately after the WRAM refresh stall?), so hang a around a bit until we enter the HBlank period
	; at the end before doing anything exciting.
	; There are 1364 master cycles per scanline and each NOP takes two CPU cycles (12~14 master cycles), and our
	; delay loop takes about 42~48 master cycles

	RW a8i16
	lda #10 ; Somewhere in the region of 450 master cycles
:
	nop	; 12~14 master cycles
	dec a ; 12~14 master cycles
	bne :- ; 18~20 master cycles (assuming branch taken)

	RW a8i16
	lda HBlankPhase
	cmp #0
	bne HBlankInterruptPhase2

	; Phase 1 - enable blanking, perform DMA

	; Turn blanking on
	RW a8i16
	lda #inidisp(OFF, DISP_BRIGHTNESS_MIN)
	sta INIDISP

	; Don't try and do DMA if a command upload is happening, as that seems to cause glitches for some reason
	lda DoingCommandUpload
	cmp #0
	bne :+

	; Perform DMA
	RW a16i16
	jsl VRAMUpload

:

	; Check we haven't already passed our expected next interrupt point
	RW a8i16
	lda SLHV
	lda OPVCT
	xba
	lda OPVCT
	and #1
	xba
	RW a16i16
	cmp #(SCREEN_DISPLAY_END_LINE - 2)
	bpl :+ ; If we're still after the end line, the raster hasn't wrapped yet and thus we're definitely well inside our timing window
	cmp #(SCREEN_DISPLAY_START_LINE - 1) ; Ensure we have at least one line spare
	bpl HBlankInterruptPhase1Overran ; If we've overrun, don't try to set up another interrupt, just immediately unblank
:
	; Set up next interrupt
	RW a8i16

	lda #1
	sta HBlankPhase

	IRQ_set SCREEN_DISPLAY_START_LINE

	jmp HBlankInterruptEnd

HBlankInterruptPhase1Overran:
	RW a16i16
	inc DMAOverrunCount ; Count number of overruns

	; Drop through to phase 2
HBlankInterruptPhase2:
	RW a8i16

	; Phase 2 - turn blanking off	
	
	RW a8i16
	lda #inidisp(ON, DISP_BRIGHTNESS_MAX)
	sta INIDISP

	; Set up next interrupt

	stz HBlankPhase
	IRQ_set SCREEN_DISPLAY_END_LINE

HBlankInterruptEnd:
	RW a16i16

	ply
	plx
	plp
	pla

	RW_pull

	rtl
endproc

; VRAM upload code
; Corrupts everything (including VRAM if you're not lucky!)
proc VRAMUpload, a16i16
	; Store registers

	pha
	php
	phx
	phy

	RW a8i16

	; Upload debug tile map data

	lda ShowDebug
	cmp #0
	bne DebugTileUpload

	; Drawing non-debug tiles

	; Move BG2 down slightly to line up the text nicely with the display bottom
	lda #$F8
	sta BG2VOFS
	lda #$FF
	sta BG2VOFS

	lda NeedNonDebugRefresh
	cmp #0
	beq :+

	RW a16i16
	VRAM_memcpy 0, NonDebugTileData, (32 * 32 * 2)
	RW a8i16
	stz NeedNonDebugRefresh
:
	jmp NoDebugUpload

DebugTileUpload:

	; Undo any BG2 move the non-debug display might have done
	stz BG2VOFS
	stz BG2VOFS

	lda DebugScreenDirtyMinY
	cmp #$7F
	bne :+
	jmp NoDebugUpload ; Nothing to do
:
	; Drawing debug tiles
	; Calculate upload start
	xba
	lda #0 ; Clear high byte
	xba
	RW a16i16
.repeat 5
	asl ; *32
.endrep
	tay ; Store for later (we need the offset in VRAM in words, hence *32 not *64)
	asl ; One more to get *64	
	add #.loword(TileData)
	tax ; Store for later

	; Calculate upload size
	RW a8i16
	lda DebugScreenDirtyMaxY
	sub DebugScreenDirtyMinY
	inc a ; Add one line because we need to transfer up to the end of MaxY
	xba
	lda #0 ; Clear high byte
	xba
	RW a16i16
.repeat 6
	asl ; *64
.endrep

	; DMA transfer, expanded from VRAM_memcpy macro because we need a bit more control here
	; X = Source offset in RAM
	; Y = Dest offset in VRAM (in words)
	; A = Number of bytes to transfer

    RW_push set:a8i16
    stz MDMAEN ; Disable DMA
	sty VMADDL ; Destination (in words)
	RW a16
	sta DAS7L ; Size
	RW a8
    stx A1T7L ; Source offset
    lda #$7e
    sta A1B7 ; Source bank
	lda #$80 ; VRAM transfer mode word access, increment by 1
    sta VMAINC
    lda #$01 ; DMA mode (word, normal, increment)
    sta DMAP7
    lda #$18 ; Destination register = VMDATA ($2118/19)
    sta BBAD7
	lda #%10000000 ; Start DMA transfer
	sta MDMAEN
    RW_pull
	RW a8

DebugUploadDone:
	; Clear dirty flags
	lda #$7f
	sta DebugScreenDirtyMinY
	stz DebugScreenDirtyMaxY
NoDebugUpload:
	RW a8i16

	; Code to run transfers at 1fps for debugging
	;lda SlowDownTimer
	;inc a
	;sta SlowDownTimer
	;cmp #60
	;beq :+
	;jmp UploadDone
;:
	;stz SlowDownTimer

	; Upload main display image
	; We upload 16000 byte blocks (exactly 16000 bytes, not 16K), which overlap in VRAM so we have to upload in a certain order to avoid
	; overwriting data which will be displayed. Specifically, if we name the three blocks A, B and C, then we do this (each step being one frame):
	; 0) Upload block A
	; 1) Upload block B and display AB
	; 2) Upload block C
	; 3) Upload block B and display BC
	; (repeat from step 1)
	; As a complicating factor, block B is very slighly different depending on which step it is uploaded in - for alignment reasons we need to
	; treat all the blocks as 16K long, but we only use 16000 bytes of them, so when uploading B in step 1 we actually upload to A+16000, but
	; when uploading in step 3 we upload to A+16K (i.e. the base of B)

	lda CurrentUploadStep
	cmp #0
	beq UploadStep0
	cmp #1
	beq UploadStep1
	cmp #2
	bne :+
	jmp UploadStep2
:
	jmp UploadStep3

UploadStep0:
	; Don't start this step if we're in the state where we're waiting for SRT to start a new frame
	lda WantNewFrame
	cmp #0
	beq :+
	jmp UploadDone
:
	; Upload block A
	lda SRTIO_MapUpperFB
	VRAM_memcpy $4000, TestImage, (8 * 8 * 250)
	lda #1
	sta CurrentUploadStep
	jmp UploadDone
UploadStep1:
	; Upload block B
	lda SRTIO_MapLowerFB
	VRAM_memcpy ($4000 + (8 * 8 * 250)), TestImage, (8 * 8 * 250)
	; Display AB
	ldx DisplayBankBG12NBASettings_AB
	stx BG12NBA
	lda #2
	sta CurrentUploadStep
	jmp UploadStartNewFrame
UploadStep2:
	; Don't start this step if we're in the state where we're waiting for SRT to start a new frame
	lda WantNewFrame
	cmp #0
	beq :+
	jmp UploadDone
:
	; Upload block C
	lda SRTIO_MapLowerFB
	VRAM_memcpy ($8000 + (8 * 8 * 250)), TestImage, (8 * 8 * 250)
	lda #3
	sta CurrentUploadStep
	jmp UploadDone
UploadStep3:
	; Upload block B
	lda SRTIO_MapUpperFB
	VRAM_memcpy $8000, TestImage, (8 * 8 * 250)
	; Display BC
	ldx DisplayBankBG12NBASettings_BC
	stx BG12NBA
	lda #0
	sta CurrentUploadStep
	; Drop through
UploadStartNewFrame:
	; Signal to the main loop to start a new frame

	lda #1
	sta WantNewFrame

UploadDone:

	RW a16i16

	ply
	plx
	plp
	pla
	
	rtl
endproc

; Main code
Main:
	RW_push set:a16i16
	lda #0 ; Clear top bits of A
	RW_pull
	RW_push set:a8i16

	; Upload palette

    lda #0
    sta CGADD
	ldx #.loword(TestPal)
	ldy #(256 * 2)
PalUploadLoop:
	lda 0, x
	sta CGDATA
	inx
	dey
	bne PalUploadLoop

	; Set screen background to green, colour 1 to white

	;CGRAM_setcolor_rgb 0, 7,31,7
	CGRAM_setcolor_rgb 1, 31,31,31
	; BG2 mode 0 palette entry 0
	;CGRAM_setcolor_rgb 33, 31,31,31

	; BG1 is the main screen, whilst BG2 is the debug text overlay

	; VRAM layout (offsets in bytes):
	; 0..2047 = BG2 tile map (32x32x2 bytes)
	; 2048..4095 = BG1 tile map (32x32x2 bytes)
	; 4096..6143 = BG3 tile map (32x32x2 bytes, required because mode 4 uses it for offset-per-tile)
	; 8192..16383 = BG2 character data (8x8x2 bytes per character x64 characters)
	; 16384..32767 = BG1 character data buffer #1 (8x8x2 bytes per character x256 characters)
	; 32768..49151 = BG1 character data buffer #2 (8x8x2 bytes per character x256 characters)
	; 49151..65535 = BG1 character data buffer #3 (8x8x2 bytes per character x256 characters)

	; Set up screen mode
	lda #bgmode(BG_MODE_4, BG3_PRIO_NORMAL, BG_SIZE_8X8, BG_SIZE_8X8, BG_SIZE_8X8, BG_SIZE_8X8)
	sta BGMODE
	; BG1 tile map at offset 2048, 32x32
	lda #bgsc(2048, SC_SIZE_32X32)
	;lda #bgsc(0, SC_SIZE_32X32)
	sta BG1SC
	; BG2 tile map at offset 0, 32x32
	lda #bgsc(0, SC_SIZE_32X32)
	sta BG2SC
	; BG2 tile map at offset 4096, 32x32
	lda #bgsc(4096, SC_SIZE_32X32)
	sta BG3SC
	; Start displaying BC initially
	ldx DisplayBankBG12NBASettings_AB ; Hack
	;ldx DisplayBankBG12NBASettings_BC
	stx BG12NBA
	; Main screen BG0 and BG1 on
	lda #tm(ON, ON, OFF, OFF, OFF)
	sta TM

	; Set up scroll to centre image
	lda #$E4 ; $10000 - ((256 - (25 * 8)) / 2)
    sta BG1HOFS
    lda #$FF
    sta BG1HOFS
	lda #$E0 ; $10000 - ((224 - (20 * 8)) / 2)
    sta BG1VOFS
    lda #$FF
    sta BG1VOFS

	; Set up BG1 window
	lda #%00000011 ; BG1 window on, clip outside
	sta W12SEL
	lda #%00000001 ; Window enabled for BG1
	sta TMW
	lda #28 ; Left edge ((256 - (25 * 8)) / 2)
	sta WH0
	lda #256 - (28 + 1) ; Right edge (256 - ((256 - (25 * 8)) / 2)
	sta WH1

	; Upload overlay character data

	lda #%10000000
	sta $2115 ; Set VRAM write increment
	ldx #4096
	stx $2116 ; Set VRAM write address

	ldy #.loword(FontData)

	lda #64; Number of characters to upload

FontUploadLoop:
	pha

	; Upload the character data - one byte occupying bitplane 0, with bitplane 1 empty
.repeat 8
	lda 0, y
	iny
	tax
	stx $2118
.endrep

	; Then upload zeroes to bitplanes 2 & 3

	ldx #0
	stz $2118
	stz $2118
	stz $2118
	stz $2118
	stz $2118
	stz $2118
	stz $2118
	stz $2118

	pla
	dec a
 	bne FontUploadLoop

	; Upload initial main display character data
	; We only have 16K of source data so for the sake of having something we upload the 16K placeholder twice

	; Since the buffers overlap this is a bit redudant, but it mimics what a real "in use" setup would be,
	; With the second buffer written as the "valid" one
	;VRAM_memcpy $4000, TestImage, (8 * 8 * 250)
	;VRAM_memcpy ($4000 + (8 * 8 * 250)), TestImage, (8 * 8 * 250)
	;VRAM_memcpy $8000, TestImage, (8 * 8 * 250)
	;VRAM_memcpy ($8000 + (8 * 8 * 250)), TestImage, (8 * 8 * 250)

	; Set up blank BG3 (tile offset map) tile data, using the tiledata buffer as working space

	ldx #.loword(TileData) 
	ldy #(32 * 32)
:
	stz 0, x
	inx
	dey
	bne :-

	VRAM_memcpy 4096, TileData, (32 * 32 * 2)

	; Set up main display tile data, using the tiledata buffer as working space
	; This just writes 25x20 indices into the 32x32 buffer space
	; We know that the tile data is filled with zeroes prior to this so we don't need
	; to write blank tiles (not that we really care deeply about their contents anyway,
	; but this is neater)

	ldx #.loword(TileData)
	lda #20 ; Num rows left
	ldy #0 ; Current tile index
MainTileDataSetupLoopY:	
	pha

	; Tiles
	lda #25 ; Num columns left
:
	sty 0, x
	inx
	inx
	iny
	dec a
	bne :-
	
	; Empty space at the end of the row
	lda #(32 - 25) ; Num columns left
:
	inx
	inx
	dec a
	bne :-

	pla
	dec a
	bne MainTileDataSetupLoopY

	; Upload to VRAM

	VRAM_memcpy 2048, TileData, (32 * 32 * 2)

	; Clear dirty flags
	lda #$7f
	sta DebugScreenDirtyMinY
	stz DebugScreenDirtyMaxY

	; Copy initial BG2 tile data to main memory buffer

	ldx #.loword(TileData)
	ldy #.loword(InitialTileData)
	lda #255
InitialTileDataCopyLoop:
	pha
.repeat 4
	lda 0, y
	sec
	sbc #32 ; Convert from ASCII to our display format
	sta 0, x
	inx
	lda #(1<<(13 - 8)) ; Set priority bit so we draw on top of the main screen
	sta 0, x
	inx	
	iny
.endrep
	pla
	dec a
	bne InitialTileDataCopyLoop

	ldx #.loword(NonDebugTileData)
	ldy #.loword(InitialNonDebugTileData)
	lda #255
InitialNonDebugTileDataCopyLoop:
	pha
.repeat 4
	lda 0, y
	sec
	sbc #32 ; Convert from ASCII to our display format
	sta 0, x
	inx
	lda #(1<<(13 - 8)) ; Set priority bit so we draw on top of the main screen
	sta 0, x
	inx	
	iny
.endrep
	pla
	dec a
	bne InitialNonDebugTileDataCopyLoop	

	; Do initial debug display upload
	VRAM_memcpy 0, TileData, (32 * 32 * 2)

	; Initialise print variables
	stz PrintX
	lda #LOG_AREA_START
	sta PrintY

	; Set up initial camera data
	RW a8i16
	ldx #.loword(InitialCameraX)
	ldy #.loword(CameraX)
	lda #(4 + 4 + 4 + 1) ; Bytes to copy
:
	pha
	lda 0, x
	sta 0, y
	inx
	iny
	pla
	dec a
	bne :-

	; Initialise stuff
	RW a16i16
	stz DMAOverrunCount
	stz CurrentUploadStep
	lda BallInitialPos0
	sta BallPos0
	lda BallInitialPos1
	sta BallPos1
	lda BallInitialPos2
	sta BallPos2
	lda BallInitialPos3
	sta BallPos3
	stz BubblePos0
	stz BubblePos1
	stz BubblePos2
	stz BubblePos3
	stz ShipPos
	stz SRTFrameCount
	stz SRTDroppedFrameCount
	RW a8i16
	lda #$FE
	sta LightYaw
	stz BoxYaw
	stz ShipAngle
	stz SlowDownTimer
	stz ShowDebug
	lda #1
	sta WantNewFrame
	sta NeedNonDebugRefresh
	stz HBlankPhase
	stz FPS
	stz MaxFPS
	stz FPSFrameCount
	stz FPSRenderedFrameCount
	stz WantNewTick
	stz TickVSyncCount
	stz DoingCommandUpload

	; Upload command list to SRT

	; First zero the upload address
	RW a8i16
	lda SRTIO_CmdWriteAddrL
	lda #0
	jsr SRTProxyWrite
	lda #0
	jsr SRTProxyWrite
	
	; Now upload the actual commands
	ldy #.loword(CommandBuffer)
	ldx #0 ; Keep a count of how many bytes we've written
	phx

	; Set the upload register (no auto-increment on this, so we can just leave it for the duration of the transfer)
	lda SRTIO_CmdWriteData8

CommandBufferUploadLoop:
	lda 0, y
	iny
	jsr SRTProxyWrite

	plx
	inx ; Increment write counter
	phx

	cpy #.loword(CommandBufferEnd)
	bne CommandBufferUploadLoop

	; Display total uploaded commands

	RW a16i16
	pla
	jsr PrintHex16
	lda #.loword(CommandUploadMsg)
	jsr PrintString
	RW a8i16
	jsr NewLine

	; Display init done message

	RW a16i16
	lda #.loword(InitDoneMsg)
	jsr PrintString
	RW a8i16
	jsr NewLine

	; Init done - enable screen
	RW a8i16
	lda #inidisp(ON, DISP_BRIGHTNESS_MAX)
	sta INIDISP

	; Turn on vblank interrupt
	VBL_set VblankInterruptHandler
	VBL_on

	; Turn on hblank interrupt
	IRQ_set SCREEN_DISPLAY_END_LINE, HblankInterruptHandler
	IRQ_on

	; Start of main loop

	;CGRAM_setcolor_rgb 0, 2,7,31

MainLoop:

	; Check if we want to do a logic tick
	; MainLoop runs as a busy-loop (in order to be able to queue new frames with SRT
	; as soon as it becomes ready), so we only actually update our logic if a VSync has
	; occurred

	RW a8i16
	lda WantNewTick
	cmp #0
	bne :+
	jmp NoTick
:
	; Don't run animation on a frame where we are going to do a command list update
	; (i.e. make sure they are interleaved)	
	lda WantNewFrame
	cmp #0
	beq :+
	jmp NoTick
:
	stz WantNewTick

	; Logic tick start

	; Calculate camera vectors
	RW a8i16
	lda CameraYaw
	jsr Sin
	stx CameraForwardX
	lda CameraYaw
	jsr Cos
	stx CameraForwardZ

	lda CameraYaw
	jsr Cos
	stx CameraRightX
	lda CameraYaw
	jsr Sin
	RW a16i16
	txa
	neg
	sta CameraRightZ
	stz CameraForwardY
	stz CameraRightY

	RW a16i16
	; Y on joypad is a shift for controls
	lda SFX_joy1cont
	bit #JOY_Y
	beq :+
	jmp ShiftControls
:
	; Regular controls

	; Camera forward/backward
	RW a16i16
	lda SFX_joy1cont
	bit #JOY_UP
	beq :+
	; Move forwards
	lda CameraForwardX
.repeat CAMERA_MOVE_SPEED_SHIFT
	asr
.endrep
	ldx #.loword(CameraX)
	jsr Add32x16Signed
	lda CameraForwardY
.repeat CAMERA_MOVE_SPEED_SHIFT
	asr
.endrep
	ldx #.loword(CameraY)
	jsr Add32x16Signed
	lda CameraForwardZ
.repeat CAMERA_MOVE_SPEED_SHIFT
	asr
.endrep
	ldx #.loword(CameraZ)
	jsr Add32x16Signed
:
	; Move backwards
	lda SFX_joy1cont
	bit #JOY_DOWN
	beq :+	
	lda CameraForwardX
.repeat CAMERA_MOVE_SPEED_SHIFT
	asr
.endrep
	neg
	ldx #.loword(CameraX)
	jsr Add32x16Signed
	lda CameraForwardY
.repeat CAMERA_MOVE_SPEED_SHIFT
	asr
.endrep
	neg
	ldx #.loword(CameraY)
	jsr Add32x16Signed
	lda CameraForwardZ
.repeat CAMERA_MOVE_SPEED_SHIFT
	asr
.endrep
	neg
	ldx #.loword(CameraZ)
	jsr Add32x16Signed
:

; Camera strafe
	RW a16i16
	lda SFX_joy1cont
	bit #JOY_R
	beq :+
	; Move right
	lda CameraRightX
.repeat CAMERA_MOVE_SPEED_SHIFT
	asr
.endrep
	ldx #.loword(CameraX)
	jsr Add32x16Signed
	lda CameraRightY
.repeat CAMERA_MOVE_SPEED_SHIFT
	asr
.endrep
	ldx #.loword(CameraY)
	jsr Add32x16Signed
	lda CameraRightZ
.repeat CAMERA_MOVE_SPEED_SHIFT
	asr
.endrep
	ldx #.loword(CameraZ)
	jsr Add32x16Signed
:
	; Move left
	lda SFX_joy1cont
	bit #JOY_L
	beq :+	
	lda CameraRightX
.repeat CAMERA_MOVE_SPEED_SHIFT
	asr
.endrep
	neg
	ldx #.loword(CameraX)
	jsr Add32x16Signed
	lda CameraRightY
.repeat CAMERA_MOVE_SPEED_SHIFT
	asr
.endrep
	neg
	ldx #.loword(CameraY)
	jsr Add32x16Signed
	lda CameraRightZ
.repeat CAMERA_MOVE_SPEED_SHIFT
	asr
.endrep
	neg
	ldx #.loword(CameraZ)
	jsr Add32x16Signed
:

	; Camera vertical movement
	RW a16i16
	lda SFX_joy1cont
	bit #JOY_A
	beq :+
	; Move down
	lda #$400 ; 1.0f / 16.0f
	ldx #.loword(CameraY)
	jsr Add32x16Signed
:
	; Move up
	lda SFX_joy1cont
	bit #JOY_X
	beq :+
	lda #$fc00 ; -1.0f / 16.0f
	ldx #.loword(CameraY)
	jsr Add32x16Signed
:

	; Camera rotation
	RW a16i16
	lda SFX_joy1cont
	bit #JOY_LEFT
	beq :+
	RW a8i16
	dec CameraYaw
	dec CameraYaw
	RW a16i16
:
	lda SFX_joy1cont
	bit #JOY_RIGHT
	beq :+
	RW a8i16
	inc CameraYaw
	inc CameraYaw
	RW a16i16
:
	jmp EndControls

ShiftControls:
	; Shifted control set

	; Light direction
	RW a16i16
	lda SFX_joy1cont
	bit #JOY_LEFT
	beq :+
	RW a8i16
	dec LightYaw
	dec LightYaw
	RW a16i16
:
	lda SFX_joy1cont
	bit #JOY_RIGHT
	beq :+
	RW a8i16
	inc LightYaw
	inc LightYaw
	RW a16i16
:

EndControls:

	; Start button toggles debug display overlay
	RW a16i16
	lda SFX_joy1cont
	bit #JOY_START
	RW a8i16
	beq NoStart
	lda OldStartState
	cmp #0
	bne StartCheckDone
	lda #1
	sta OldStartState
	lda ShowDebug
	cmp #0
	beq :+
	; Turn debug display off
	stz ShowDebug
	stz MaxFPS ; Clear max FPS when turning off
	; Trigger non-debug screen refresh
	lda #1
	sta NeedNonDebugRefresh
	jmp StartCheckDone
:
	; Turn debug display on
	lda #1
	sta ShowDebug
	; Invalidate whole screen
	stz DebugScreenDirtyMinY
	lda #31
	sta DebugScreenDirtyMaxY
	jmp StartCheckDone
NoStart:
	stz OldStartState
StartCheckDone:

	; Update animation

	RW a8i16

	; Select to advance animation
	;lda SFX_joy1trig
	;bit #JOY_SELECT
	;beq NoAnim

	; Update ball animations

	RW a16i16
	
	lda #.loword(BallPos0)
	sta Temp1
	lda #.loword(BallVel0)
	sta Temp2
	jsr UpdateBallAnim

	lda #.loword(BallPos1)
	sta Temp1
	lda #.loword(BallVel1)
	sta Temp2
	jsr UpdateBallAnim

	lda #.loword(BallPos2)
	sta Temp1
	lda #.loword(BallVel2)
	sta Temp2
	jsr UpdateBallAnim

	lda #.loword(BallPos3)
	sta Temp1
	lda #.loword(BallVel3)
	sta Temp2
	jsr UpdateBallAnim

	; Update bubble positions
	lda BubblePos0
	add BubbleVel0
	sta BubblePos0
	lda BubblePos1
	add BubbleVel1
	sta BubblePos1
	lda BubblePos2
	add BubbleVel2
	sta BubblePos2
	lda BubblePos3
	add BubbleVel3
	sta BubblePos3

	; Update ship angle and recalculate position
	RW a8i16
	inc ShipAngle
	lda ShipAngle
	jsr Sin
	RW a16i16
	txa
	asr ; Divide motion amount by 2
	add ShipBobCentre
	sta ShipPos

	; Update rotated plane vectors for cubes

	RW a16i16
	lda #.loword(CommandBuffer + (COMMAND_EDIT_POINT_4 * 8))
	sta Temp10
	lda #6 ; Number of planes to rotate
	sta Temp11
	lda #.loword(Cube1PlaneBuffer)
	sta Temp12
	RW a8i16
	lda BoxYaw
	jsr RotatePlanesYaw

	; Calculate rotated plane normals for the second cube
	RW a16i16
	lda #.loword(CommandBuffer + (COMMAND_EDIT_POINT_5 * 8))
	sta Temp10
	lda #6 ; Number of planes to rotate
	sta Temp11
	lda #.loword(Cube2PlaneBuffer)
	sta Temp12
	RW a8i16
	lda BoxYaw
	jsr RotatePlanesYaw	

NoAnim:
NoTick:

	; Start uploading new data to the SRT if required
	; We can only do this if the chip is idle and we've displayed the previous frame,
	; so we check both WantNewFrame and SRTIO_Status

	; Only do this if we actually want a new frame
	lda WantNewFrame
	cmp #0
	bne :+	
	jmp NoNewFrame
:

	; Check if SRT is actually ready to start a new frame
	lda SRTIO_Status
	and #1
	beq :+
	jmp SRTDroppedFrame ; Cannot start new frame because SRT chip is still rendering the last one we submitted
:
	; Set ray parameters

	RW a8i16
	lda #1
	sta DoingCommandUpload

	; Camera position
	RW a16i16
	lda CameraX
	sta RayParameters_RayStartX
	lda CameraX + 2
	sta RayParameters_RayStartX + 2
	lda CameraY
	sta RayParameters_RayStartY
	lda CameraY + 2
	sta RayParameters_RayStartY + 2
	lda CameraZ
	sta RayParameters_RayStartZ
	lda CameraZ + 2
	sta RayParameters_RayStartZ + 2

	; Ray (fustrum) setup, rotated by camera orientation
	RW a8i16
	ldx #.loword(BaseRayParameters_RayDir)
	ldy #.loword(RayParameters_RayDirX)
	lda CameraYaw
	jsr RotateVectorYaw

	ldx #.loword(BaseRayParameters_RayDirXStep)
	ldy #.loword(RayParameters_RayDirXStepX)
	lda CameraYaw
	jsr RotateVectorYaw

	ldx #.loword(BaseRayParameters_RayDirYStep)
	ldy #.loword(RayParameters_RayDirYStepX)
	lda CameraYaw
	jsr RotateVectorYaw
		
	; Upload ray parameters to SRT

	RW a8i16
	lda SRTIO_RayStartX0 ; Initialise IO register address to the first parameter register (will auto-increment after this)
	lda #30 ; Number of bytes we need to upload to the ray parameter registers
	ldy #.loword(RayParameters)
:
	pha
	lda 0, y
	iny
	jsr SRTProxyWrite
	pla
	dec a
	bne :-

	; Calculate light direction
	RW a8i16
	ldx #.loword(BaseLightDir)
	ldy #.loword(LightDir)
	lda LightYaw
	jsr RotateVectorYaw

	; Upload light direction to SRT
	RW a8i16
	lda SRTIO_LightDirXL ; Initialise IO register address to the first parameter register (will auto-increment after this)
	lda #6 ; Number of bytes we need to upload to the ray parameter registers
	ldy #.loword(LightDir)
:
	pha
	lda 0, y
	iny
	jsr SRTProxyWrite
	pla
	dec a
	bne :-

	; Write ball positions to SRT command list

	RW a16i16
	lda #COMMAND_EDIT_POINT_0
	sta Temp3
	lda #.loword(CommandBuffer + (COMMAND_EDIT_POINT_0 * 8))
	sta Temp4
	lda BallPos0
	jsr UpdateSphereOrOriginY

	lda #COMMAND_EDIT_POINT_1
	sta Temp3
	lda #.loword(CommandBuffer + (COMMAND_EDIT_POINT_1 * 8))
	sta Temp4
	lda BallPos1
	jsr UpdateSphereOrOriginY

	lda #COMMAND_EDIT_POINT_2
	sta Temp3
	lda #.loword(CommandBuffer + (COMMAND_EDIT_POINT_2 * 8))
	sta Temp4
	lda BallPos2
	jsr UpdateSphereOrOriginY	

	lda #COMMAND_EDIT_POINT_3
	sta Temp3
	lda #.loword(CommandBuffer + (COMMAND_EDIT_POINT_3 * 8))
	sta Temp4
	lda BallPos3
	jsr UpdateSphereOrOriginY

	; Write bubble positions to SRT command list

	RW a16i16
	lda #COMMAND_EDIT_POINT_6
	sta Temp3
	lda #.loword(CommandBuffer + (COMMAND_EDIT_POINT_6 * 8))
	sta Temp4
	lda BubblePos0
	jsr UpdateSphereOrOriginY

	lda #COMMAND_EDIT_POINT_7
	sta Temp3
	lda #.loword(CommandBuffer + (COMMAND_EDIT_POINT_7 * 8))
	sta Temp4
	lda BubblePos1
	jsr UpdateSphereOrOriginY

	lda #COMMAND_EDIT_POINT_8
	sta Temp3
	lda #.loword(CommandBuffer + (COMMAND_EDIT_POINT_8 * 8))
	sta Temp4
	lda BubblePos2
	jsr UpdateSphereOrOriginY

	lda #COMMAND_EDIT_POINT_9
	sta Temp3
	lda #.loword(CommandBuffer + (COMMAND_EDIT_POINT_9 * 8))
	sta Temp4
	lda BubblePos3
	jsr UpdateSphereOrOriginY

	; Write ship position to SRT command list
	lda #COMMAND_EDIT_POINT_10
	sta Temp3
	lda #.loword(CommandBuffer + (COMMAND_EDIT_POINT_10 * 8))
	sta Temp4
	lda ShipPos
	jsr UpdateSphereOrOriginY
	
	; Write cube plane normal to SRT command list
	RW a16i16
	lda #COMMAND_EDIT_POINT_4
	sta Temp9
	lda #.loword(CommandBuffer + (COMMAND_EDIT_POINT_4 * 8))
	sta Temp10
	lda #6 ; Number of planes to write
	sta Temp11
	lda #.loword(Cube1PlaneBuffer)
	sta Temp12
	RW a8i16
	jsr UpdatePlanes

	; Write cube plane normal for second cube to SRT command list
	RW a16i16
	lda #COMMAND_EDIT_POINT_5
	sta Temp9
	lda #.loword(CommandBuffer + (COMMAND_EDIT_POINT_5 * 8))
	sta Temp10
	lda #6 ; Number of planes to rotate
	sta Temp11
	lda #.loword(Cube2PlaneBuffer)
	sta Temp12
	RW a8i16
	jsr UpdatePlanes

	; Tell SRT to start a new frame with this data

	RW a8i16
	lda SRTIO_NewFrame ; Tell SuperRT to swap buffers and start a new frame
	stz WantNewFrame ; Clear want new frame flag
	RW a16i16
	inc SRTFrameCount ; Increment our frame count
	inc FPSRenderedFrameCount
	RW a8i16

	stz DoingCommandUpload

	jmp NoNewFrame

SRTDroppedFrame:
	; We get here if the SRT wasn't ready to start a new frame yet
	RW_push set:a16i16
	inc SRTDroppedFrameCount
	RW_pull

NoNewFrame:
	RW a8i16

	; Update FPS
	lda FPSFrameCount
	cmp #60
	bmi NoFPSUpdate
	lda FPSRenderedFrameCount
	sta FPS
	cmp MaxFPS ; Update max FPS
	bmi :+
	sta MaxFPS
:
	stz FPSRenderedFrameCount
	stz FPSFrameCount	
NoFPSUpdate:

	; Only update debug display if it's actually visible
	lda ShowDebug
	cmp #0
	bne :+
	jmp DebugPrintDone
:

	; Draw frame counter	
	PushPrintLoc 1, 9
	RW a16i16
	lda SFX_tick
	jsr PrintHex16
	RW a8i16
	; Print SRT frame counter
	SetPrintLoc 7, 9
	RW a16i16
	lda SRTFrameCount
	jsr PrintHex16
	RW a8i16
	; Print SRT drop count
	SetPrintLoc 14, 9
	RW a16i16
	lda SRTDroppedFrameCount
	jsr PrintHex16
	RW a8i16		
	; Print DMA overrun count
	SetPrintLoc 22, 9
	RW a16i16
	lda DMAOverrunCount
	jsr PrintHex16
	RW a8i16

	; Print SRT status flag
	RW a8i16
	SetPrintLoc 12, 14
	lda SRTIO_Status
	jsr PrintHex8

	; Print FPS/max FPS
	RW a8i16
	SetPrintLoc 22, 14
	lda FPS
	jsr PrintHex8
	RW a8i16
	SetPrintLoc 29, 14
	lda MaxFPS
	jsr PrintHex8

	; Print camera pos
	SetPrintLoc 1, 11
	RW a16i16
	lda #.loword(CameraX)
	jsr PrintHex32
	RW a8i16
	SetPrintLoc 10, 11
	RW a16i16
	lda #.loword(CameraY)
	jsr PrintHex32
	RW a8i16
	SetPrintLoc 19, 11
	RW a16i16
	lda #.loword(CameraZ)
	jsr PrintHex32
	RW a8i16
	SetPrintLoc 28, 11
	lda CameraYaw
	jsr PrintHex8	

	; Print light dir
	SetPrintLoc 5, 12
	RW a16i16
	lda LightDirX
	jsr PrintHex16
	RW a8i16
	SetPrintLoc 14, 12
	RW a16i16
	lda LightDirY
	jsr PrintHex16
	RW a8i16
	SetPrintLoc 23, 12
	RW a16i16
	lda LightDirZ
	jsr PrintHex16
	RW a8i16

	; Print light yaw
	RW a8i16
	SetPrintLoc 28, 12
	lda LightYaw
	jsr PrintHex8

	; Print ray dir start
	SetPrintLoc 5, 13
	RW a16i16
	lda RayParameters_RayDirX
	jsr PrintHex16
	RW a8i16
	SetPrintLoc 14, 13
	RW a16i16
	lda RayParameters_RayDirY
	jsr PrintHex16
	RW a8i16
	SetPrintLoc 23, 13
	RW a16i16
	lda RayParameters_RayDirZ
	jsr PrintHex16
	RW a8i16
	PopPrintLoc
DebugPrintDone:

	; Normally we'd wait for VBlank here, but we want to be able to start a new frame as soon as possible,
	; so we loop infinitely. Logic is instead tied to VBlank by means of the WantNewTick flag.
	; (except there were glitches with that, so do wait!)
	wai

	jmp MainLoop

	RW_pull

	; Update the animation for a ball
	; Temp1 = BallPos address
	; Temp2 = BallVel address
	; Corrupts everything
proc UpdateBallAnim, a16i16
	; BallPos += BallVel
	ldx Temp1
	ldy Temp2
	lda 0, x 
	add 0, y
	sta 0, x
	; BallVel += BallGrav, and clamp to BallTermVel
	lda 0, y
	add BallGrav
	sta 0, y
	; Collide ball with floor
	lda 0, x
	and #$8000
	bne :+ ; Cheeky negative check
	lda 0, x
	cmp BallFloor
	bmi :+
	lda BallFloor
	sta 0, x
	lda 0, y
	neg
	sta 0, y
:
	; Clamp to terminal velocity
	lda 0, y
	and #$8000
	bne :+ ; Cheeky negative check
	lda 0, y
	cmp BallTermVel
	bmi :+
	lda BallTermVel
	sta 0, y
:
	; Update the box rotation
	RW a8i16
	inc BoxYaw
	RW a16i16
	rts
endproc

	; Update the Y position of a sphere or origin command in the SRT command list
	; A (16 bit) = Y position in 2.14 format
	; Temp3 = Command buffer offset on SRT
	; Temp4 = Address of local command buffer data
	; Corrupts everything
proc UpdateSphereOrOriginY, a16i16	
	; Convert position to 8.7 format (we start in 2.14, so shift right 7 times)	
.repeat 7
	asr
.endrep
	sta Temp5

	; First set the upload address
	RW a8i16
	lda SRTIO_CmdWriteAddrL	
	lda Temp3 ; Offset in SRT command buffer
	jsr SRTProxyWrite
	ldx #.loword(Temp3)
	lda 1, x
	jsr SRTProxyWrite

	; Start uploading
	RW a16i16
	ldy Temp4 ; Offset of our local copy of the command data
	RW a8i16
	; Byte 0 (8 bits)
	lda SRTIO_CmdWriteData8
	lda 0, y
	jsr SRTProxyWrite
	; Byte 1 (8 bits)
	lda SRTIO_CmdWriteData8
	lda 1, y
	jsr SRTProxyWrite
	; Byte 2 (8 bits)
	lda SRTIO_CmdWriteData8
	lda 2, y
	jsr SRTProxyWrite
	; Byte 3 (2 bits)
	lda SRTIO_CmdWriteData2
	lda 3, y
.repeat 6
	asr
.endrep
	jsr SRTProxyWrite	
	; High byte of position (7 bits, bytes 3-4)
	lda SRTIO_CmdWriteData7
	ldx #.loword(Temp5 + 1)
	lda 0, x
	jsr SRTProxyWrite
	; Low byte of position (8 bits, bytes 4-5)
	lda SRTIO_CmdWriteData8
	lda Temp5
	jsr SRTProxyWrite
	; Remainder of byte 5 (7 bits)
	lda SRTIO_CmdWriteData7
	lda 5, y
	jsr SRTProxyWrite
	; Byte 6
	lda SRTIO_CmdWriteData8
	lda 6, y
	jsr SRTProxyWrite
	; Byte 7
	lda SRTIO_CmdWriteData8
	lda 7, y
	jsr SRTProxyWrite
	RW a16i16
	rts
endproc

	; Rotate a number of planes in the command list
	; A (8 bit) = Yaw
	; Temp10 = Address of local command buffer data (overwritten)
	; Temp11 = Number of planes to rotate (overwritten)
	; Temp12 = Rotated plane data pointer (overwritten)
	; Corrupts everything
proc RotatePlanesYaw, a8i16
	pha

RotatePlanesYaw_Loop:

	; First extract the current plane normal from the command
	ldy Temp10

	lda 5, y ; X high bits (4 bits)
	and #$F
	bit #$8
	beq :+
	ora #$F0 ; Sign-extend
:
	xba
	lda 6, y ; X low bits (8 bits)
	RW a16i16
	sta PlaneNormalSrcX

	RW a8i16
	lda 4, y ; Y high bits (8 bits)
	xba
	lda 5, y ; Y low bits (4 bits)
	RW a16i16
.repeat 4
	asr
.endrep
	sta PlaneNormalSrcY

	RW a8i16
	lda 2, y ; Z high bits (4 bits)
	and #$F
	bit #$8
	beq :+
	ora #$F0 ; Sign-extend
:	
	xba
	lda 3, y ; Z low bits (8 bits)
	RW a16i16
	sta PlaneNormalSrcZ

	; Now PlaneNormalSrc contains the original vector, in 2.10 format
	; We don't need to convert to 2.14 because rotation doesn't care about the vector being scaled, so
	; we can rotate as-is and save ourselves the trouble. However we *do* need to sign-extend into the
	; upper four bits (which we did above)

	; Rotate the normal vector

	ldx #.loword(PlaneNormalSrcX)
	ldy Temp12
	RW a8i16
	pla ; Pull the yaw value
	pha ; And put it back for later
	jsr RotateVectorYaw	

	; Increment command list address
	RW a16i16
	lda Temp10
	add #8
	sta Temp10

	; Increment write address
	RW a16i16
	lda Temp12
	add #6
	sta Temp12

	RW a8i16
	dec Temp11 ; Decrement plane count
	RW a8i16
	beq :+
	jmp RotatePlanesYaw_Loop
:
	pla ; Discard our stored yaw value
	rts
endproc	

	; Write rotated planes to the command list
	; Temp9 = Command buffer offset on SRT (overwritten)
	; Temp10 = Address of local command buffer data (overwritten)
	; Temp11 = Number of planes to rotate (overwritten)
	; Temp12 = Rotated plane data pointer (overwritten)
	; Corrupts everything
proc UpdatePlanes, a8i16
	; Now we need to write the updated command to the SRT command buffer

UpdatePlanes_Loop:

	ldy Temp10 ; Local command data

	; First set the upload address
	RW a8i16
	lda SRTIO_CmdWriteAddrL	
	lda Temp9 ; Offset in SRT command buffer
	jsr SRTProxyWrite
	ldx #.loword(Temp9)
	lda 1, x
	jsr SRTProxyWrite

	; Byte 0 (8 bits)
	lda SRTIO_CmdWriteData8
	lda 0, y
	jsr SRTProxyWrite
	; Byte 1 (8 bits)
	lda SRTIO_CmdWriteData8
	lda 1, y
	jsr SRTProxyWrite

	; Byte 2 (4 bits)
	lda SRTIO_CmdWriteData4
	lda 2, y
.repeat 4
	asr
.endrep
	jsr SRTProxyWrite
	; Top 4 bits of normal Z
	lda SRTIO_CmdWriteData4
	ldx Temp12
	lda 5, x
	jsr SRTProxyWrite
	; Bottom 8 bits of normal Z
	lda SRTIO_CmdWriteData8
	ldx Temp12
	lda 4, x
	jsr SRTProxyWrite
	; Top 4 bits of normal Y
	lda SRTIO_CmdWriteData4
	ldx Temp12
	lda 3, x
	jsr SRTProxyWrite
	; Bottom 8 bits of normal Y
	lda SRTIO_CmdWriteData8
	ldx Temp12
	lda 2, x
	jsr SRTProxyWrite
	; Top 4 bits of normal X
	lda SRTIO_CmdWriteData4
	ldx Temp12
	lda 1, x
	jsr SRTProxyWrite
	; Bottom 8 bits of normal X
	lda SRTIO_CmdWriteData8
	ldx Temp12
	lda 0, x
	jsr SRTProxyWrite
	; Byte 7 (8 bits)
	lda SRTIO_CmdWriteData8
	lda 7, y
	jsr SRTProxyWrite

	; Increment command list addresses
	RW a16i16
	inc Temp9
	lda Temp10
	add #8
	sta Temp10

	; Increment rotated plane data address
	lda Temp12
	add #6
	sta Temp12

	dec Temp11 ; Decrement plane count
	RW a8i16
	beq :+
	jmp UpdatePlanes_Loop
:
	rts
endproc

	; Rotates the 16-bit 3-element vector pointed at by X by the 8-bit yaw angle in A, writing the results to Y
	; Assumes vector components are <=1 (more specifically, that they fit in 16 bits in fixed-point format, which is ~<4-ish)
	; Corrupts A, X and Y and Temp1-Temp8
proc RotateVectorYaw, a8i16
	; Store addresss in Temp7 (input)/Temp8 (output)
	stx Temp7
	sty Temp8
	pha
	; Copy Y across from input to output as it doesn't get modified by yaw
	RW a16i16
	lda 2, x
	sta 2, y
	RW a8i16
	; Calculate sin(a) and cos(a) and store in Temp5/Temp6
	pla
	pha
	jsr Sin
	stx Temp5
	pla
	jsr Cos
	stx Temp6

	RW a16i16
	; X' = (X * cos(a)) + (Z * sin(a))
	; Calculate X * cos(a)
	lda Temp6
	sta Temp1
	ldx Temp7
	lda 0, x
	sta Temp2
	jsr FixedMul16x16Signed
	lda Temp3 ; Low word of result, we don't need the high word as we know these values are small enough
	pha ; Store X * cos(a) on stack
	; Calculate Z * sin(a)
	lda Temp5
	sta Temp1
	ldx Temp7
	lda 4, x
	sta Temp2
	jsr FixedMul16x16Signed
	pla ; Retrieve X * cos(a)
	add Temp3 ; Add to Z * sin(a)
	ldx Temp8
	sta 0, x ; Store in output vector

	; Z' = (Z * cos(a)) - (X * sin(a))
	; Calculate Z * cos(a)
	lda Temp6
	sta Temp1
	ldx Temp7
	lda 4, x
	sta Temp2
	jsr FixedMul16x16Signed
	lda Temp3 ; Low word of result, we don't need the high word as we know these values are small enough
	pha ; Store Z * cos(a) on stack
	; Calculate X * sin(a)
	lda Temp5
	sta Temp1
	ldx Temp7
	lda 0, x
	sta Temp2
	jsr FixedMul16x16Signed
	pla ; Retrieve Z * cos(a)
	sub Temp3 ; Subtract X * sin(a)
	ldx Temp8
	sta 4, x ; Store in output vector	

	RW a8i16
	rts
endproc

	; Adds the sign-extended 16 bit value in A to the 32-bit value pointed to by X
	; Corrupts A and Y
proc Add32x16Signed, a16i16
	; Sign-extend A into Y
	ldy #0
	cmp #0
	bpl :+
	ldy #$ffff
:
	; Perform 32-bit addition
	clc
	adc 0, x
	sta 0, x
	tya
	adc 2, x
	sta 2, x
	rts
endproc

	; Perform a proxied write to an IO register on the SuperRT chip
	; The register to write to must be set beforehand (by reading it)
	; The value to write should be in A
	; Corrupts A and X
proc SRTProxyWrite, a8i16
	xba
	lda #$BF ; Set upper byte to upper byte of SRTIO_WriteProxy
	xba
	tax
	lda 0, x ; Perform read (proxied write)
	rts
endproc

	; Multiplies 16-bit signed fixed-point values in Temp1 and Temp2, putting the 32-bit result in Temp3 and Temp4 (high word in Temp4)
	; Uses the hardware multiply unit on the SuperRT chip
	; Corrupts everything
proc FixedMul16x16Signed, a16i16

	; Write inputs to SRT registers

	RW a8i16
	lda SRTIO_MulAL ; Initialise IO register address
	lda Temp1
	jsr SRTProxyWrite
	lda Temp1 + 1
	jsr SRTProxyWrite
	lda Temp2
	jsr SRTProxyWrite
	lda Temp2 + 1
	jsr SRTProxyWrite

	; Read result
	RW a16i16
	lda SRTIO_MulO0
	sta Temp3
	lda SRTIO_MulO2
	sta Temp4
	rts
endproc

	; Takes an 8-bit angle (256 = 360 degrees) in A and returns the 16-bit sin of it in X
	; Corrupts A and X
proc Sin, a8i16
	RW a16i16
	and #$FF
	asl a ; *2 because there are two bytes per entry
	add #.loword(SinTable)
	tax
	lda 0, x
	tax
	RW a8i16
	rts
endproc

	; Takes an 8-bit angle (256 = 360 degrees) in A and returns the 16-bit cosine of it in X
	; Corrupts A and X
proc Cos, a8i16
	pha
	pla ; Throw away stack value (but leave it in memory so we can read it)
	lda #64
	sub 0, s ; cos(a) = sin(90 - a)
	jmp Sin
endproc

	; Print an 8-bit value in A as hex
	; Corrupts A, X, Y
proc PrintHex8, a8i16	
	pha

	; High nibble
	ClearHighByteOfA
.repeat 4
	lsr a
.endrep
	RW a16i16
	add #.loword(HexTable)
	tax
	RW a8i16
	lda 0, x

	jsr PrintChar

	pla
	; Low nibble
	ClearHighByteOfA
	and #$F
	RW a16i16
	add #.loword(HexTable)
	tax
	RW a8i16
	lda 0, x

	jsr PrintChar
	
	rts
endproc

	; Print a 16-bit value in A as hex
	; Corrupts A, X, Y
proc PrintHex16, a16i16
	pha

	; High word
.repeat 8
	lsr a
.endrep

	RW a8i16
	jsr PrintHex8
	RW a16i16

	pla
	; Low word
	and #$FF
	RW a8i16
	jsr PrintHex8
	RW a16i16

	rts
endproc

	; Print a 32-bit value whose address is in A as hex
	; Corrupts A, X, Y
proc PrintHex32, a16i16
	tax	
	lda 3, x
	phx
	RW a8i16
	jsr PrintHex8
	RW a16i16
	plx
	lda 2, x
	phx
	RW a8i16
	jsr PrintHex8
	RW a16i16
	plx
	lda 1, x
	phx
	RW a8i16
	jsr PrintHex8
	RW a16i16
	plx
	lda 0, x
	RW a8i16
	jsr PrintHex8
	RW a16i16
	rts
endproc

	; Print a zero-terminated string, address in A, followed by a newline
	; Corrupts A, X, Y
proc PrintLine, a16i16
	jsr PrintString
	RW a8i16
	jsr NewLine
	RW a16i16
	rts
endproc

	; Print a zero-terminated string, address in A
	; Corrupts A, X, Y
proc PrintString, a16i16
	tax
	RW a8i16
PrintLoop:	
	lda 0, x
	cmp #0
	beq Done
	phx
	jsr PrintChar
	plx
	inx
	jmp PrintLoop
Done:
	RW a16i16
	rts
endproc

LOG_AREA_START = 16 ; Line the scroll area starts at
PRINT_AREA_HEIGHT = 22 ; Number of lines of screen we have to print to

	; Move the print location to the start of a new line
	; Corrupts A, X, Y
proc NewLine, a8i16
	stz PrintX
	inc PrintY
	lda PrintY
	cmp #PRINT_AREA_HEIGHT
	bne Nowrap

	; Scroll the screen
	jsr ScrollScreen
	dec PrintY ; Keep printing to the bottom line
Nowrap:
	rts
endproc

	; Scroll the screen up one line
	; Does not alter the print position
	; Corrupts A, X, Y
proc ScrollScreen, a8i16
	; Scroll the screen buffer
	memcpy TileData + (LOG_AREA_START * 32 * 2), TileData + ((LOG_AREA_START + 1) * 32 * 2), ((PRINT_AREA_HEIGHT - LOG_AREA_START) * 32 * 2)
	; Clear the final line
	ldx #TileData + (32 * (PRINT_AREA_HEIGHT - 1) * 2)
	ldy #32
ClearLoop:
	stz 0, x
	inx
	inx ; Skip second byte - we don't want to nuke the priority bit
	dey
	bne ClearLoop

	; Update dirty region
	lda DebugScreenDirtyMinY
	cmp #LOG_AREA_START
	bmi :+
	lda #LOG_AREA_START
	sta DebugScreenDirtyMinY
:
	lda #PRINT_AREA_HEIGHT
	cmp DebugScreenDirtyMaxY
	bmi :+
	sta DebugScreenDirtyMaxY
:

	rts
endproc

	; Print an ASCII character in A at the current print co-ordinates and increment them
	; Corrupts A, X, Y
proc PrintChar, a8i16
	sub #32 ; Convert ASCII to tile index
	pha

	; Calculate offset into tile data

	RW a16i16
	lda #0
	RW a8i16
	lda PrintY
	RW a16i16
.repeat 5
	asl ; *32
.endrep
	RW a8i16 ; Safe because we know adding X will never cause an overflow
	add PrintX
	RW a16i16
	asl ; *2 because each tile is two bytes

	add #TileData ; Add offset to tile data
	tax ; X is now the tile write pointer

	RW a8i16

	pla ; Retrieve tile index to write
	sta 0, x ; Write to tile

	; Update dirty region
	lda DebugScreenDirtyMinY
	cmp PrintY
	bmi :+
	lda PrintY
	sta DebugScreenDirtyMinY
:
	lda PrintY
	cmp DebugScreenDirtyMaxY
	bmi :+
	sta DebugScreenDirtyMaxY
:

	; Move forward one character
	inc PrintX
	lda PrintX
	cmp #32
	bne Nowrap

	; Move to the next line
	stz PrintX
	inc PrintY
	lda PrintY
	cmp #PRINT_AREA_HEIGHT
	bne Nowrap

	; Scroll the screen
	jsr ScrollScreen
	dec PrintY ; Keep printing to the bottom line
Nowrap:
	rts
endproc

.segment "LORAM"
; Print call X/Y
PrintX: .res 1
PrintY: .res 1
DMAOverrunCount: .res 2
CurrentUploadStep: .res 1
SlowDownTimer: .res 1
ShowDebug: .res 1
OldStartState: .res 1
NeedNonDebugRefresh: .res 1
HBlankPhase: .res 1
DebugScreenDirtyMinY: .res 1 ; Minimum updated row (or $7F for no updates)
DebugScreenDirtyMaxY: .res 1 ; Maximum updated row
SRTFrameCount: .res 2 ; SRT rendered frame count
SRTDroppedFrameCount: .res 2 ; SRT dropped frame count
WantNewFrame: .res 1 ; 1 if we should start a new frame
WantNewTick: .res 1 ; 1 if we should do a new logic tick (20hz, purely for animation speed reasons)
TickVSyncCount: .res 1 ; How many vsyncs have elapsed since the last tick
FPS: .res 1 ; Current FPS
MaxFPS: .res 1 ; Highest FPS seen (resets when turning off debug display)
FPSFrameCount: .res 1 ; FPS overall frame counter
FPSRenderedFrameCount: .res 1 ; FPS rendered frame counter
DoingCommandUpload: .res 1
; Generic temp storage
Temp1: .res 2
Temp2: .res 2
Temp3: .res 2
Temp4: .res 2
Temp5: .res 2
Temp6: .res 2
Temp7: .res 2
Temp8: .res 2
Temp9: .res 2
Temp10: .res 2
Temp11: .res 2
Temp12: .res 2
; Camera position
CameraX: .res 4
CameraY: .res 4
CameraZ: .res 4
CameraYaw: .res 1
; Light direction
LightYaw: .res 1
; Camera forward/right axes
CameraForwardX: .res 2
CameraForwardY: .res 2
CameraForwardZ: .res 2
CameraRightX: .res 2
CameraRightY: .res 2
CameraRightZ: .res 2
RayParameters: ; SRT ray parameters (30 bytes total)
RayParameters_RayStartX: .res 4 
RayParameters_RayStartY: .res 4
RayParameters_RayStartZ: .res 4
RayParameters_RayDirX: .res 2
RayParameters_RayDirY: .res 2
RayParameters_RayDirZ: .res 2
RayParameters_RayDirXStepX: .res 2
RayParameters_RayDirXStepY: .res 2
RayParameters_RayDirXStepZ: .res 2
RayParameters_RayDirYStepX: .res 2
RayParameters_RayDirYStepY: .res 2
RayParameters_RayDirYStepZ: .res 2
LightDir: ; Light direction (3x2 bytes)
LightDirX: .res 2
LightDirY: .res 2
LightDirZ: .res 2
; Ball positions
BallPos0: .res 2
BallPos1: .res 2
BallPos2: .res 2
BallPos3: .res 2
BallVel0: .res 2
BallVel1: .res 2
BallVel2: .res 2
BallVel3: .res 2
; Rotating box yaw
BoxYaw: .res 1
; Temp for plane rotation
PlaneNormalSrcX: .res 2
PlaneNormalSrcY: .res 2
PlaneNormalSrcZ: .res 2
PlaneNormalDestX: .res 2
PlaneNormalDestY: .res 2
PlaneNormalDestZ: .res 2
; Bubble positions
BubblePos0: .res 2
BubblePos1: .res 2
BubblePos2: .res 2
BubblePos3: .res 2
; Ship position
ShipPos: .res 2
ShipAngle: .res 1
; Plane work buffers
Cube1PlaneBuffer: .res (6 * 6)
Cube2PlaneBuffer: .res (6 * 6)

TileData:
	.res (32 * 32 * 2) ; Space for tile data in display format
NonDebugTileData:
	.res (32 * 32 * 2) ; Space for non-debug tile data in display format

.segment "SRT"

incbin TestImage, "Data/Placeholder.bin"

; This ends at $BE80

; IO registers from $BE80

.org $BE80

; Frame management
SRTIO_NewFrame: .res 1
SRTIO_MapUpperFB: .res 1
SRTIO_MapLowerFB: .res 1

; Ray parameters
SRTIO_RayStartX0: .res 1
SRTIO_RayStartX1: .res 1
SRTIO_RayStartX2: .res 1
SRTIO_RayStartX3: .res 1
SRTIO_RayStartY0: .res 1
SRTIO_RayStartY1: .res 1
SRTIO_RayStartY2: .res 1
SRTIO_RayStartY3: .res 1
SRTIO_RayStartZ0: .res 1
SRTIO_RayStartZ1: .res 1
SRTIO_RayStartZ2: .res 1
SRTIO_RayStartZ3: .res 1
SRTIO_RayDirXL: .res 1
SRTIO_RayDirXH: .res 1
SRTIO_RayDirYL: .res 1
SRTIO_RayDirYH: .res 1
SRTIO_RayDirZL: .res 1
SRTIO_RayDirZH: .res 1
SRTIO_RayDirXStepXL: .res 1
SRTIO_RayDirXStepXH: .res 1
SRTIO_RayDirXStepYL: .res 1
SRTIO_RayDirXStepYH: .res 1
SRTIO_RayDirXStepZL: .res 1
SRTIO_RayDirXStepZH: .res 1
SRTIO_RayDirYStepXL: .res 1
SRTIO_RayDirYStepXH: .res 1
SRTIO_RayDirYStepYL: .res 1
SRTIO_RayDirYStepYH: .res 1
SRTIO_RayDirYStepZL: .res 1
SRTIO_RayDirYStepZH: .res 1

; Multiplication unit
SRTIO_MulAL: .res 1
SRTIO_MulAH: .res 1
SRTIO_MulBL: .res 1
SRTIO_MulBH: .res 1
SRTIO_MulO0: .res 1
SRTIO_MulO1: .res 1
SRTIO_MulO2: .res 1
SRTIO_MulO3: .res 1

; Command list write
SRTIO_CmdWriteAddrL: .res 1 ; Write address low byte
SRTIO_CmdWriteAddrH: .res 1 ; Write address high byte
SRTIO_CmdWriteData1: .res 1 ; Write data (1 bit)
SRTIO_CmdWriteData2: .res 1 ; Write data (2 bits)
SRTIO_CmdWriteData3: .res 1 ; Write data (3 bits)
SRTIO_CmdWriteData4: .res 1 ; Write data (4 bits)
SRTIO_CmdWriteData5: .res 1 ; Write data (5 bits)
SRTIO_CmdWriteData6: .res 1 ; Write data (6 bits)
SRTIO_CmdWriteData7: .res 1 ; Write data (7 bits)
SRTIO_CmdWriteData8: .res 1 ; Write data (8 bits)

; Lighting
SRTIO_LightDirXL: .res 1
SRTIO_LightDirXH: .res 1
SRTIO_LightDirYL: .res 1
SRTIO_LightDirYH: .res 1
SRTIO_LightDirZL: .res 1
SRTIO_LightDirZH: .res 1

; Status information
; This is a little bit of a cheat for debugging in emulator - setting SRTIO_Status to zero makes the (non-existent)
; SRT chip appear to be never busy and thus the main update loop actually runs
SRTIO_Status: .byte 0

; Write proxy area $BF00 - BFFF
.org $BF00
SRTIO_WriteProxy: .res $100

.segment "RODATA"

incbin SinTable, "Data/SinTable.bin"
incbin TestPal, "Data/MainPal.bin"
incbin CommandBuffer, "Data/CommandBuffer.bin"
CommandBufferEnd:

; Settings for the BG12 register for each of the two display banks
DisplayBankBG12NBASettings_AB: ; Settings for displaying buffers A & B
	.word bgnba($4000, 8192, 0, 0)
DisplayBankBG12NBASettings_BC: ; Settings for displaying buffers B & C
	.word bgnba($8000, 8192, 0, 0)

; Initial camera data
InitialCameraX: .dword $00015D27
InitialCameraY: .dword $00002C00
InitialCameraZ: .dword $FFFF909C
InitialCameraYaw: .byte $C9

; Base ray parameters, which define the view fustrum
; These get rotated by the camera orientation and then uploaded to the SRT chip
BaseRayParameters_RayDir:
	.word $e5e3 ; RayParameters_RayDirX
	.word $e5e3 ; RayParameters_RayDirY
	.word $3445 ; RayParameters_RayDirZ
BaseRayParameters_RayDirXStep:
	.word $0042 ; RayParameters_RayDirXStepX
	.word $0000 ; RayParameters_RayDirXStepY
	.word $0000 ; RayParameters_RayDirXStepZ
BaseRayParameters_RayDirYStep:
	.word $0000 ; RayParameters_RayDirYStepX
	.word $0042 ; RayParameters_RayDirYStepY
	.word $0000 ; RayParameters_RayDirYStepZ

; Base light direction
BaseLightDir:
	.word $24f3
	.word $db0d
	.word $db0d

; Ball animation parameters
BallGrav: ; 0.05f
	.word $0333
BallFloor: ; 1.5f
	.word $6000 
BallTermVel: ; 0.4f
	.word $1999
BallInitialPos0:
	.word $0000
BallInitialPos1:
	.word $2000
BallInitialPos2:
	.word $4000
BallInitialPos3:
	.word $6000

; Bubble animation parameters
BubbleVel0: .word $feb9
BubbleVel1: .word $fd71
BubbleVel2: .word $fc29
BubbleVel3: .word $fae2

; Ship animation parameters
ShipBobCentre: .word $3ccc ; 0.95f

FrameMsg:
	.byte "FRAME = "
	.byte 0

CommandUploadMsg:
	.byte " CMD BYTES UPLOADED"
	.byte 0

InitDoneMsg:
	.byte "INIT DONE"
	.byte 0

InitialTileData:
	.byte "                                "
	.byte "        NEKOMIMI MODE!          "
	.byte "                                "
	.byte "                                " ; Last blanked line (partially visible)
	.byte "                                "
	.byte "__ SUPERRT TEST HARNESS V0.05 __"
	.byte "      SHIRONEKO LABS 2020       "
	.byte "________________________________"
	.byte " FRAME SRTFRM SRTOVER DMAOVER   "
	.byte " XXXX  XXXX   XXXX    XXXX      "
	.byte " CAM X    CAM Y    CAM Z    YAW "
	.byte " XXXXXXXX XXXXXXXX XXXXXXXX XX  "
	.byte " LGT XXXX     XXXX     XXXX XX  "
	.byte " CDR XXXX     XXXX     XXXX     "
	.byte " SRT STATUS XX    FPS XX MAX XX "
	.byte "________________________________"
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "                                " ; First blanked line (partially visible)
	.byte " ALL THIS TEXT IS HIDDEN BY THE "
	.byte " FORCED BLANKING FOR THE DMA.   "
	.byte " TECHNICALLY THE LINE DIRECTLY  "
	.byte " ABOVE IS VISIBLE, BUT CLIPPED. "
	.byte "                                "
	.byte " HELLO TO ANYONE READING THIS!  "
	.byte " EITHER YOU'RE LOOKING AT THE   "
	.byte " CODE, OR THERE'S A TERRIBLE BUG"

InitialNonDebugTileData:
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "                                " ; Last blanked line (partially visible)
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "    [\]^             :;<=>?@    " ; This looks weird but some of the otherwise unused font characters are reused to get a 5x3 small font
	.byte "                                " ; First blanked line (partially visible)
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "                                "
	.byte "                                "

HexTable:
	.byte "0123456789ABCDEF"

FontData:
; 32
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000

	.byte %00000000
	.byte %00010000
	.byte %00010000
	.byte %00010000
	.byte %00010000
	.byte %00010000
	.byte %00000000
	.byte %00010000

	.byte %00000000
	.byte %01000010
	.byte %01000010
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000

	.byte %00000000
	.byte %00100100
	.byte %01111110
	.byte %00100100
	.byte %00100100
	.byte %01111110
	.byte %00100100
	.byte %00100100

	.byte %00000000
	.byte %00111110
	.byte %01010000
	.byte %01010000
	.byte %00111100
	.byte %00010010
	.byte %00010010
	.byte %01111100

	.byte %00000000
	.byte %00100000
	.byte %00100010
	.byte %00000100
	.byte %00001000
	.byte %00010000
	.byte %00100010
	.byte %00000010

	.byte %00000000
	.byte %00111100
	.byte %01100010
	.byte %01010000
	.byte %01001000
	.byte %01000100
	.byte %01000010
	.byte %00111100

	.byte %00000000
	.byte %00010000
	.byte %00010000
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000

; 40
	.byte %00000000
	.byte %00000010
	.byte %00000100
	.byte %00000100
	.byte %00000100
	.byte %00000100
	.byte %00000100
	.byte %00000010

	.byte %00000000
	.byte %01000000
	.byte %00100000
	.byte %00100000
	.byte %00100000
	.byte %00100000
	.byte %00100000
	.byte %01000000

	.byte %00000000
	.byte %01010010
	.byte %00111100
	.byte %01111110
	.byte %00010000
	.byte %00011000
	.byte %00110100
	.byte %01010100

	.byte %00000000
	.byte %00000000
	.byte %00010000
	.byte %00010000
	.byte %01111110
	.byte %00010000
	.byte %00010000
	.byte %00010000

	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000100
	.byte %00000100
	.byte %00001000
	.byte %00000000

	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %01111110
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000

	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000110
	.byte %00000110
	.byte %00000000

	.byte %00000000
	.byte %00000000
	.byte %00000010
	.byte %00000100
	.byte %00001000
	.byte %00010000
	.byte %00100000
	.byte %01000000

	.byte %00000000
	.byte %01111110
	.byte %01000010
	.byte %01000010
	.byte %01000010
	.byte %01000010
	.byte %01000010
	.byte %01111110

	.byte %00000000
	.byte %00000010
	.byte %00000010
	.byte %00000010
	.byte %00000010
	.byte %00000010
	.byte %00000010
	.byte %00000010

; 50
	.byte %00000000
	.byte %01111110
	.byte %00000010
	.byte %00000010
	.byte %01111110
	.byte %01000000
	.byte %01000000
	.byte %01111110

	.byte %00000000
	.byte %01111110
	.byte %00000010
	.byte %00000010
	.byte %01111110
	.byte %00000010
	.byte %00000010
	.byte %01111110

	.byte %00000000
	.byte %01000000
	.byte %01000000
	.byte %01000000
	.byte %01010000
	.byte %01111110
	.byte %00010000
	.byte %00010000

	.byte %00000000
	.byte %01111110
	.byte %01000000
	.byte %01000000
	.byte %01111110
	.byte %00000010
	.byte %00000010
	.byte %01111110

	.byte %00000000
	.byte %01000000
	.byte %01000000
	.byte %01000000
	.byte %01111110
	.byte %01000010
	.byte %01000010
	.byte %01111110

	.byte %00000000
	.byte %01111110
	.byte %00000010
	.byte %00000010
	.byte %00000010
	.byte %00000010
	.byte %00000010
	.byte %00000010

	.byte %00000000
	.byte %01111110
	.byte %01000010
	.byte %01000010
	.byte %01111110
	.byte %01000010
	.byte %01000010
	.byte %01111110

	.byte %00000000
	.byte %01111110
	.byte %01000010
	.byte %01000010
	.byte %01111110
	.byte %00000010
	.byte %00000010
	.byte %00000010

	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %01110101
	.byte %01000101
	.byte %01110111
	.byte %00010101
	.byte %01110101

	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %01110111
	.byte %00100101
	.byte %00100111
	.byte %00100110
	.byte %01110101

; 60
	; These characters form "SHIRONEKO LABS" in a 3x5 font
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %01110111
	.byte %01010101
	.byte %01010101
	.byte %01010101
	.byte %01110101

	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %01110101
	.byte %01000101
	.byte %01100110
	.byte %01000101
	.byte %01110101

	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %01110000
	.byte %01010000
	.byte %01010000
	.byte %01010000
	.byte %01110000

	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %01000010
	.byte %01000101
	.byte %01000111
	.byte %01000101
	.byte %01110101

	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %01100111
	.byte %01010100
	.byte %01100111
	.byte %01010001
	.byte %01100111

	; End of "SHIRONEKO LABS" text

	.byte %00000000
	.byte %00111100
	.byte %01000010
	.byte %01000010
	.byte %01111110
	.byte %01000010
	.byte %01000010
	.byte %01000010

	.byte %00000000
	.byte %01111100
	.byte %01000010
	.byte %01000010
	.byte %01111100
	.byte %01000010
	.byte %01000010
	.byte %01111100

	.byte %00000000
	.byte %00111110
	.byte %01000000
	.byte %01000000
	.byte %01000000
	.byte %01000000
	.byte %01000000
	.byte %00111110

	.byte %00000000
	.byte %01111100
	.byte %01000010
	.byte %01000010
	.byte %01000010
	.byte %01000010
	.byte %01000010
	.byte %01111100

	.byte %00000000
	.byte %01111110
	.byte %01000000
	.byte %01000000
	.byte %01111100
	.byte %01000000
	.byte %01000000
	.byte %01111110

; 70
	.byte %00000000
	.byte %01111110
	.byte %01000000
	.byte %01111100
	.byte %01000000
	.byte %01000000
	.byte %01000000
	.byte %01000000

	.byte %00000000
	.byte %01111100
	.byte %01000010
	.byte %01000000
	.byte %01001110
	.byte %01000010
	.byte %01000010
	.byte %00111100

	.byte %00000000
	.byte %01000010
	.byte %01000010
	.byte %01000010
	.byte %01111110
	.byte %01000010
	.byte %01000010
	.byte %01000010

	.byte %00000000
	.byte %01111110
	.byte %00010000
	.byte %00010000
	.byte %00010000
	.byte %00010000
	.byte %00010000
	.byte %01111110

	.byte %00000000
	.byte %01111110
	.byte %00010000
	.byte %00010000
	.byte %00010000
	.byte %00010000
	.byte %01010000
	.byte %01110000

	.byte %00000000
	.byte %01000100
	.byte %01001000
	.byte %01010000
	.byte %01100000
	.byte %01010000
	.byte %01001000
	.byte %01000100

	.byte %00000000
	.byte %01000000
	.byte %01000000
	.byte %01000000
	.byte %01000000
	.byte %01000000
	.byte %01000000
	.byte %01111110

	.byte %00000000
	.byte %00111100
	.byte %01010010
	.byte %01010010
	.byte %01010010
	.byte %01000010
	.byte %01000010
	.byte %01000010

	.byte %00000000
	.byte %00111100
	.byte %01000010
	.byte %01000010
	.byte %01000010
	.byte %01000010
	.byte %01000010
	.byte %01000010

	.byte %00000000
	.byte %00111100
	.byte %01000010
	.byte %01000010
	.byte %01000010
	.byte %01000010
	.byte %01000010
	.byte %00111100

	.byte %00000000
	.byte %01111100
	.byte %01000010
	.byte %01000010
	.byte %01111100
	.byte %01000000
	.byte %01000000
	.byte %01000000

	.byte %00000000
	.byte %00111100
	.byte %01000010
	.byte %01000010
	.byte %01000010
	.byte %01001010
	.byte %01000110
	.byte %00111110

	.byte %00000000
	.byte %00111100
	.byte %01000010
	.byte %01000010
	.byte %01111100
	.byte %01100000
	.byte %01010000
	.byte %01001100

	.byte %00000000
	.byte %00111100
	.byte %01000000
	.byte %01000000
	.byte %00111100
	.byte %00000010
	.byte %00000010
	.byte %00111100

	.byte %00000000
	.byte %01111110
	.byte %00010000
	.byte %00010000
	.byte %00010000
	.byte %00010000
	.byte %00010000
	.byte %00010000

	.byte %00000000
	.byte %01000010
	.byte %01000010
	.byte %01000010
	.byte %01000010
	.byte %01000010
	.byte %01000010
	.byte %00111100

	.byte %00000000
	.byte %01000010
	.byte %01000010
	.byte %00100100
	.byte %00100100
	.byte %00100100
	.byte %00011000
	.byte %00011000

	.byte %00000000
	.byte %01000010
	.byte %01000010
	.byte %01000010
	.byte %01010010
	.byte %01010010
	.byte %01010010
	.byte %00111100

	.byte %00000000
	.byte %01000010
	.byte %01000010
	.byte %00100100
	.byte %00011000
	.byte %00100100
	.byte %01000010
	.byte %01000010

	.byte %00000000
	.byte %01000010
	.byte %01000010
	.byte %00100100
	.byte %00011000
	.byte %00010000
	.byte %00010000
	.byte %00010000

	.byte %00000000
	.byte %01111110
	.byte %00000100
	.byte %00001000
	.byte %00010000
	.byte %00100000
	.byte %01000000
	.byte %01111110

	; These characters form "SUPERRT" in a 3x5 font

	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %01110101
	.byte %01000101
	.byte %01110101
	.byte %00010101
	.byte %01110111

	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %01110111
	.byte %01010100
	.byte %01110110
	.byte %01000100
	.byte %01000111

	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %01110111
	.byte %01010101
	.byte %01110111
	.byte %01100110
	.byte %01010101

	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %01110000
	.byte %00100000
	.byte %00100000
	.byte %00100000
	.byte %00100000

	; _ is a horizontal line
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %11111111
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000

	; This gives us 64 characters
