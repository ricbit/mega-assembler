; Mega-Assembler (MSX cartridge, Portuguese; resident Z80 assembler/monitor)
; Disassembled by Ricardo Bittencourt (bluepenguin@gmail.com)
; Last update at 2026-05-25
;
	output "mega.bin"
	org 04000h

X_REG_NAME_BASE_HIGH             equ     044D8h    ; Offset-arithmetic base used by X for IX/IY/SP/PC name lookup (=IXIY+8)
X_REG_NAME_BASE_LOW              equ     044E0h    ; Offset-arithmetic base used by X for 8-bit register name lookup (=IXIY+16)
PAGE_3_RAM                       equ     0C000h    ; Top of page-3 RAM — destination of COPY_PROTECTION_FAIL's LDIR-wipe payload
MEGA_PAGE_HEIGHT                 equ     0EC00h    ; Lines-per-page setting; reloaded into DISASM_LINES_LEFT at each page break
MEGA_SRC_BUF_START               equ     0EC01h    ; Lowest address of the source-text buffer; computed from BIOS_BOTTOM at init
MEGA_SRC_BUF_HEAD                equ     0EC03h    ; Address of the most recently written source byte (= START-1 when empty)
MEGA_SRC_BUF_END                 equ     0EC05h    ; Highest writable byte of the source buffer (BIOS_HIMEM-2 at init)
MEGA_USER_CODE_END               equ     0EC07h    ; Upper bound of user-code write window — ASM_EMIT_BYTE skips writes above this
MEGA_USER_CODE_START             equ     0EC09h    ; Lower bound of user-code write window (EBFFh at boot)
MEGA_SRC_LINE_PTR                equ     0EC0Bh    ; Address of the current source line being walked (LOCATE_LINE_BY_NUMBER output)
MEGA_LINE_NUMBER                 equ     0EC0Dh    ; Last parsed line number (written by PARSE_LINE_NUMBER, read by PROMPT_TICK)
MEGA_AUTO_FIRST_FLAG             equ     0EC13h    ; AUTO-mode flag: 0 = first auto prompt (no increment), nonzero = subsequent
MEGA_AUTO_LINE_NUMBER            equ     0EC14h    ; Current AUTO line number printed at each prompt
MEGA_AUTO_LINE_INCREMENT         equ     0EC16h    ; AUTO step (typically 10) added to MEGA_AUTO_LINE_NUMBER each iteration
MEGA_LIST_LINE_PTR               equ     0EC18h    ; Address of the current source line during LIST/RENUM/DELETE iteration
MEGA_SEARCH_PATTERN              equ     0EC1Ah    ; Pointer to the search-pattern string (SEARCH/FIND/CHANGE)
MEGA_CHANGE_REPLACE              equ     0EC1Ch    ; Pointer to the CHANGE replacement string (after the second '/' separator)
MEGA_CHANGE_SRC_PTR              equ     0EC1Eh    ; Source-line walk pointer during CHANGE / DELETE byte-by-byte rewrite
MEGA_CHANGE_DST_PTR              equ     0EC20h    ; Destination pointer (in scratch at EE18) where CHANGE writes the rebuilt line
MEGA_LINE_RANGE_END              equ     0EC22h    ; End source-line pointer for DELETE / CHANGE / RENUM range operations
MEGA_AUTO_FIRST_ARG              equ     0EC24h    ; First arg of AUTO (line-number start) stashed by AUTO_PARSE_ARGS at 5005h
MEGA_CHANGE_FOUND                equ     0EC25h    ; Set/cleared by CHANGE to mark whether the search pattern matched in this line
MEGA_PASS1_DONE_FLAG             equ     0EC26h    ; FFh once PASS1 of MEGA_ASSEMBLE has completed; reset to 0 by `NEW`
MEGA_ASM_STATE_AREA              equ     0EC27h    ; Start of 25-byte zeroed assembler scratch (zeroed by INIT_ASSEMBLER_STATE)
MEGA_PROCNM_PTR                  equ     0EC29h    ; Pointer init'd to BIOS_PROCNM (FD89h) — accesses the BASIC CALL name buffer
MEGA_USER_REGS_SAVE              equ     0EC2Bh    ; User-program register snapshot (IY, IX, I, HL, DE, BC, AF, …) for G/X
MEGA_I_REG_SAVE                  equ     0EC2Fh    ; Saved Z80 I (interrupt page) register from before the assembler took over
MEGA_USER_FLAGS_SAVE             equ     0EC3Eh    ; Saved F register printed by PRINT_FLAGS_AS_LETTERS as S/Z/V/C glyphs
MEGA_USER_REGS_TAIL              equ     0EC3Fh    ; End of the 8-byte saved-register block (EC37..EC3F walked by MEGA_PCMD_X_SHOW)
MEGA_ASM_STACK_TOP               equ     0EC40h    ; Initial SP for the assembler's private stack (grows downward into EC3F..EC27)
MEGA_SAVED_SP_X                  equ     0EC41h    ; Word slot saving caller SP before MEGA_PCMD_X/G switches to the assembler stack
MEGA_LAST_MEM_ADDR               equ     0EC43h    ; Last-accessed address — remembered between successive `M addr` invocations
MEGA_DISASM_LAST_END             equ     0EC45h    ; Last-disassembled instruction end address — boot-zeroed, updated per-instr
DISASM_SPECIAL_MATCH_FLAG        equ     0EC47h    ; FFh after DISASM_SPECIAL_DISPATCH matches an opcode in DISASM_SPECIAL_OPCODES
MEGA_SYM_TABLE_BASE              equ     0EC49h    ; Pointer to the start of the assembler's symbol table (walked by LOOKUP_LABEL)
MEGA_SYM_TABLE_END               equ     0EC4Bh    ; Upper bound of the symbol table (set to user-code-region end at boot)
MEGA_ASM_PASS2_START             equ     0EC4Dh    ; Saved MEGA_SRC_BUF_START at MEGA_ASSEMBLE entry; seeds MEGA_ASM_PASS2_CURSOR
MEGA_ASM_PASS2_CURSOR            equ     0EC4Fh    ; PASS-2 cursor stash for line emission (saved/restored at 523D / 5245 / 527F)
MEGA_ASM_OPERAND_VAL             equ     0EC51h    ; Parsed operand value (16-bit): ASM_PARSE_EXPRESSION writes, encoders read
MEGA_ASM_OPERAND_VAL_HI          equ     0EC52h    ; High byte of MEGA_ASM_OPERAND_VAL (16-bit operand value, low at EC51)
MEGA_ASM_IXY_DISP                equ     0EC53h    ; IXY displacement byte (the `±d` of `(IX+d)`) parsed by ASM_PARSE_OPERAND
MEGA_ASM_OPERAND_FLAG            equ     0EC54h    ; Per-operand transient flag — set during parse, cleared by ASM_EMIT_OPCODE
MEGA_ASM_OPC_FLAGS               equ     0EC55h    ; Modifier flags: bit 1 = FD (IY) vs DD (IX), bit 2 = needs prefix
MEGA_ASM_OP_SIGN                 equ     0EC56h    ; Sign char (`'+'` or `'-'`) of the next term in ASM_PARSE_EXPRESSION
MEGA_DISASM_OPCODE               equ     0EC57h    ; Saved opcode byte for the current disasm — DISASM_EMIT_OPERANDS reads it here
MEGA_ASM_IXY_PREFIX              equ     0EC58h    ; Saved IX/IY prefix byte (DD/FD) for opcode emit
DISASM_LINES_LEFT                equ     0EC59h    ; Countdown of remaining lines on the current page (reload = MEGA_PAGE_HEIGHT)
DISASM_PAGE_NUMBER               equ     0EC5Ah    ; Current page number — printed after MEGA_TOP_BANNER then incremented
MEGA_SYM_VALUE_PTR               equ     0EC5Ch    ; Address where the next symbol value (2 bytes after the name) will be written
MEGA_DISASM_CURSOR               equ     0EC5Eh    ; Current user-code address — ASM_EMIT_BYTE writes, READ_NEXT_USER_BYTE reads
MEGA_DISASM_CURSOR_HI            equ     0EC5Fh    ; High byte of MEGA_DISASM_CURSOR — used for adc-carry math at OP_JR_TARGET
MEGA_DISASM_INSTR_START          equ     0EC60h    ; Address of the first byte of the instruction currently being disassembled
MEGA_ASM_CURRENT_LINE            equ     0EC62h    ; Current source-line number being assembled (read from the 2-byte line prefix)
MEGA_ASM_CURRENT_LINE_HI         equ     0EC63h    ; High byte of MEGA_ASM_CURRENT_LINE (line number is a 16-bit word)
MEGA_SYM_TABLE_HEAD              equ     0EC64h    ; Address of the next free slot in the assembler symbol table
MEGA_SAVED_SP_ASM                equ     0EC66h    ; Caller SP stashed by MEGA_ASSEMBLE at entry; restored on error / completion
MEGA_ASM_LINE_SP                 equ     0EC68h    ; Per-line SP snapshot inside PASS-2; restored before processing the next line
MEGA_LIST_BUF_COUNT              equ     0EC6Ah    ; 8-bit byte counter into a 256-byte line buffer at EE16h (LIST/SAVE output)
MEGA_LIST_FROM_OFFSET            equ     0EC6Bh    ; Toggle: 1 = print from ECC9 (mnemonic column only) skipping the 4-digit address
MEGA_ASM_PASS1_FLAG_LO           equ     0EC6Ch    ; Low byte of PASS-1 per-line state, cleared at 51DCh on each new line
MEGA_PCMD_C_MODE                 equ     0EC6Dh    ; Bytes-per-line mode set by `C n` (0=4 bytes, 1=16 bytes, 2=8 with checksum)
BREAKPOINT_A_OPCODE              equ     0EC6Eh    ; `RST 18` opcode (DFh) for breakpoint slot A; followed by 2-byte target address
MEGA_BP_A_ADDR                   equ     0EC6Fh    ; Breakpoint slot A target address (2 bytes after BREAKPOINT_A_OPCODE)
BREAKPOINT_B_OPCODE              equ     0EC71h    ; `RST 18` opcode (DFh) for breakpoint slot B; followed by 2-byte target address
MEGA_BP_B_ADDR                   equ     0EC72h    ; Breakpoint slot B target address (2 bytes after BREAKPOINT_B_OPCODE)
BIOS_HOUTD_PASSTHROUGH           equ     0EC74h    ; Saved 5 bytes of BIOS HOUTD; jumped to on no breakpoint match
MEGA_TAPE_REC_COUNT              equ     0EC79h    ; Byte count (0..15) in the current Intel-Hex record buffer; flushed at 16
MEGA_TAPE_REC_ADDR               equ     0EC7Ah    ; Start address of the Intel-Hex record being built in MEGA_TAPE_REC_BUF
MEGA_TAPE_REC_BUF                equ     0EC7Ch    ; 16-byte buffer holding bytes for the current Intel-Hex record before flush
MEGA_ASM_BYTES_BUF               equ     0EC8Eh    ; Per-line buffer of assembled bytes; iy advances here as ASM_EMIT_BYTE writes
MEGA_ASM_BYTES_BUF_END           equ     0ECACh    ; Upper bound check — ASM_LINE_DB_DW raises overflow if iy reaches here
MEGA_LABEL_NAME                  equ     0ECAFh    ; 6-byte buffer holding the most recently parsed label/symbol name
MEGA_LABEL_NAME_TAIL             equ     0ECB0h    ; MEGA_LABEL_NAME+1 — ASM_MNEMONIC_MATCH_RECORD compares from 2nd-char onward
MEGA_LIST_LABEL_DUMP_COL         equ     0ECBFh    ; 5-char label-dump column used by ASM_PRINT_SYMBOLS (offset MEGA_DISASM_LINE-4)
MEGA_DIRBUF_SAV                  equ     0ECC1h    ; Saved BIOS_DIRBUF cell value — restored on exit via MEGA_RETURN_TO_BASIC
MEGA_DISASM_LINE                 equ     0ECC3h    ; 80-byte (50h) output line buffer where D-command builds each disassembled row
MEGA_DISASM_LINE_CR              equ     0ECC4h    ; Slot inside MEGA_DISASM_LINE where ASM_LINE_EMPTY stamps a CR terminator
MEGA_DISASM_HEX_COL              equ     0ECC8h    ; Hex-dump column start inside MEGA_DISASM_LINE (iy=ECC8 for DISASM_HEXDUMP_LOOP)
MEGA_DISASM_MNEMONIC_COL         equ     0ECC9h    ; Mnemonic column inside MEGA_DISASM_LINE (offset +6)
MEGA_LIST_ADDR_COL               equ     0ECCCh    ; 4-digit address column inside MEGA_DISASM_LINE (LIST output)
MEGA_LIST_REFS_COL               equ     0ECCFh    ; Per-reference dump column used by ASM_DUMP_SYMBOL_REFS_LOOP
MEGA_DISASM_OPERAND_COL          equ     0ECD1h    ; Operand column inside MEGA_DISASM_LINE (offset +14, where DISASM_EMIT_* writes)
MEGA_DISASM_HEX_END_C0           equ     0ECD5h    ; Hex-dump end column when `C 0` (4 bytes/row) mode is active
MEGA_DISASM_HEX_END_FAIL         equ     0ECD6h    ; Alt iy reset (ECD5+1) used when DISASM lookup fails — emits `db` literal
MEGA_LIST_LABEL_COL              equ     0ECDAh    ; Label column inside MEGA_DISASM_LINE for LIST output (offset +23)
MEGA_LIST_MNEM_COL               equ     0ECE1h    ; Mnemonic column inside MEGA_DISASM_LINE for LIST output (offset +30)
MEGA_DISASM_HEX_END_C2           equ     0ECE5h    ; Hex-dump end column when `C 2` (8 bytes/row + checksum) mode is active
MEGA_LIST_OPND_COL               equ     0ECE6h    ; Operand column inside MEGA_DISASM_LINE for LIST output (offset +35)
MEGA_LIST_COMMENT_COL            equ     0ECF4h    ; Comment column inside MEGA_DISASM_LINE for LIST output (offset +49)
MEGA_DISASM_HEX_END_C1           equ     0ECF9h    ; Hex-dump end column when `C 1` (16 bytes/row) mode is active
MEGA_LIST_LABEL_END              equ     0ED12h    ; Upper bound for ASM_LIST_LABEL_BODY copy when offset-mode is off
MEGA_DISASM_LINE_END             equ     0ED13h    ; One-past-end sentinel of MEGA_DISASM_LINE — DISASM_CLEAR_LINE predec start
MEGA_ASM_LINE_BUF                equ     0ED14h    ; Source-line text buffer fed to assembler/SKIP_SPACES_RAW
MEGA_LIST_LABEL_END_LONG         equ     0ED18h    ; Upper bound when MEGA_LIST_FROM_OFFSET is set (address column suppressed)
MEGA_LIST_BUF                    equ     0EE16h    ; 256-byte output buffer used by LIST/SAVE; counter at MEGA_LIST_BUF_COUNT
MEGA_CHANGE_TARGET               equ     0EE18h    ; Replacement-pattern buffer used by CHANGE command (inside MEGA_LIST_BUF region)
MEGA_TAPE_HDR_FILENAME           equ     0EE27h    ; Filename field in tape header buffer (16 bytes, EE27-EE36)
MEGA_FILE_BUF_IDX                equ     0F975h    ; Current index into MEGA_FILE_BUFFER; 80h = "buffer empty, refill required"
MEGA_FILE_BUFFER                 equ     0F976h    ; 128-byte buffered-I/O area for FILE_READ_BYTE / FILE_WRITE_BYTE
MEGA_STATE_FLAGS                 equ     0F9F5h    ; 1-byte flag register read via IX (bit 3 / bit 7 tested in MEGA_PROMPT_TICK)
MEGA_ASM_PASS_FLAG               equ     0F9F6h    ; Cleared at MEGA_ASSEMBLE entry; signals PASS-1/PASS-2 phase to inner emitters
MEGA_ASM_LINE_FLAG               equ     0F9F7h    ; Per-line "active-emit" flag, cleared by 52A9 at start of each PASS-1 line
MEGA_ASM_RELOC_OFFSET            equ     0F9F8h    ; Offset added to MEGA_DISASM_CURSOR for actual write address (PASS-2)
MEGA_SAVED_HL                    equ     0F9FAh    ; HL stash on entry to MEGA_INIT_BODY (`ld (F9FAh),hl` at 404A)
MEGA_SAVED_SP                    equ     0F9FCh    ; SP stash on entry to MEGA_INIT_BODY — restored at top of MEGA_PROMPT_LOOP
MEGA_INPUT_LINE_PTR              equ     0F9FEh    ; Pointer into the current input line consumed by MEGA_PROMPT_TICK
MEGA_HOOK_SLOT_PATCH             equ     0FA03h    ; SMC primary-slot byte inside MEGA_HOOK_FA00 (cart slot for `out (A8h),a`)
MEGA_HOOK_SUBSLOT_PATCH          equ     0FA0Ah    ; SMC subslot byte inside MEGA_HOOK_FA08 — cart subslot for FFFFh write
MEGA_HEADER_TYPE                 equ     0FA30h    ; Cassette-header type marker (D0/D3/EAh) AND scratch start-addr for DM/ZAP
MEGA_SLOT_PATCH                  equ     0FA31h    ; High byte of FA30 — used as subslot patch storage by MEGA_INSTALL_DRIVER
MEGA_SCRATCH_W2                  equ     0FA32h    ; Second word of the FA30 scratch — `dst` for COPY*, `end` for DM/ZAP, etc.
MEGA_SCRATCH_W2_HI               equ     0FA33h    ; High byte of MEGA_SCRATCH_W2 — written separately by DM/ZAP and SCR
MEGA_SCRATCH_W3                  equ     0FA34h    ; Third word of the FA30 scratch — `len` for COPY*, exec-addr for HEADER, etc.
MEGA_SCRATCH_W3_HI               equ     0FA35h    ; High byte of MEGA_SCRATCH_W3 — written separately by DM/ZAP and SCR
MEGA_EDITOR_MODE_FLAGS           equ     0FA36h    ; Editor state bitmap: bit 7 = active, bit 6 = (CTRL-X), bit 5 = graphics mode
DM_ZAP_MODE                      equ     0FA37h    ; DM/ZAP shared body's mode flag: 0 = display memory, 1 = zap (fill with 0)
MEGA_DM_OFFSET                   equ     0FA38h    ; Signed byte offset added by DM_FETCH_BYTE — set via `D start,offset`
MEGA_EDITOR_CURSOR_POS           equ     0FA39h    ; Editor cursor: high nibble = row, low nibble = column (0..15)
MEGA_EDITOR_DATA_BASE            equ     0FA3Ah    ; Base address being edited — argument of `CALL EDITOR addr`
MEGA_EDITOR_CELL_BUF             equ     0FA3Ch    ; 16-byte buffer holding the current editor cell's pattern data being modified
MEGA_EDITOR_ROW_OFF              equ     0FA5Ch    ; Cached row offset (= MEGA_SCRATCH_W2 * 8) for the current cell's arithmetic
MEGA_EDITOR_COL_OFF              equ     0FA5Eh    ; Cached column offset (row_offset + 8) used by COPY_8_FROM_HEADER_BASE
MEGA_EDITOR_INVERT               equ     0FA74h    ; Bit 0 = invert flag: when set, editor complements bytes before BIOS_WRTVRM
MEGA_HKEYC_SAVE                  equ     0FFD9h    ; Cart's save slot for the original BIOS_HKEYC hook (restored on `BA` exit)

BIOS_ENSTOP                      equ     0FBB0h    ; CTRL+STOP enable flag (0 = STOP raises BREAK; nonzero = STOP suppressed)
BIOS_BOTTOM                      equ     0FC48h    ; lowest RAM address available to BASIC (2 bytes, LE)
BIOS_HIMEM                       equ     0FC4Ah    ; highest RAM address available to BASIC (2 bytes, LE)
BIOS_CAPST                       equ     0FCABh    ; CAPS-lock LED state mirror
BIOS_GRPACX                      equ     0FCB7h    ; Graphic-mode "actual X" cursor word (BIOS_GRPPRT origin)
BIOS_GRPACY                      equ     0FCB9h    ; Graphic-mode "actual Y" cursor word
BIOS_SCRMOD                      equ     0FCAFh    ; Current screen mode (0=text, 1=GRAPHIC, 2=GRAPHIC2, 3=MULTI)
BIOS_EXPTBL                      equ     0FCC1h    ; Slot-0..3 expansion flags (80h = expanded, 0 = not)
BIOS_SLTTBL                      equ     0FCC5h    ; Mirror of secondary-slot selection registers for slots 0..3
BIOS_RG1SAV                      equ     0F3E0h    ; Mirror of VDP register 1 (the F3DFh+ duplicate mirror — first instance)
BIOS_T32COL                      equ     0F3BFh    ; SCREEN 1 (32-col) colour-table base pointer (set by INIT32)
BIOS_RG7SAV                      equ     0F3E6h    ; Mirror of VDP register 7 (border/text colours)
BIOS_NAMBAS                      equ     0F922h    ; Current text-mode VDP name-table base (set by INITXT/INIT32)
BIOS_CGPBAS                      equ     0F924h    ; Current text-mode VDP character-pattern-table base
BIOS_PATBAS                      equ     0F926h    ; Current sprite-pattern-table base (text/graphic-2/multicolour)
BIOS_DIRBUF                      equ     0F351h    ; Disk BASIC lowest-safe-RAM / DSKI$/DSKO$ buffer; MEGA bumps to SP+FD00h
BIOS_CURLIN                      equ     0F41Ch    ; BASIC interpreter's current-line-number cell (FFFFh in direct mode)
BIOS_GRPNAM                      equ     0F3C7h    ; VDP name-table base pointer for SCREEN 2 (graphics mode)
BIOS_GRPCOL                      equ     0F3C9h    ; VDP colour-table base pointer for SCREEN 2 (graphics mode)
BIOS_GRPCGP                      equ     0F3CBh    ; VDP character-pattern table base pointer for SCREEN 2
BIOS_MLTNAM                      equ     0F3D1h    ; VDP name-table base pointer for SCREEN 3 (multicolour mode)
BIOS_MLTCGP                      equ     0F3D5h    ; VDP character-pattern table base pointer for SCREEN 3
BIOS_TXTTAB                      equ     0F676h    ; BASIC Program Text Area pointer (start of tokenised program)
BIOS_VARTAB                      equ     0F6C2h    ; BASIC Variable Table pointer
BIOS_ARYTAB                      equ     0F6C4h    ; BASIC Array Table pointer
BDOS                             equ     0F37Dh    ; MSX-DOS BDOS dispatcher — call BDOS with C = BDOS_xxx function code
BDOS_OPEN                        equ     0000Fh    ; _FOPEN — open file by FCB
BDOS_CLOSE                       equ     00010h    ; _FCLOSE — close file by FCB
BDOS_RDSEQ                       equ     00014h    ; _RDSEQ — sequential read 128-byte record
BDOS_WRSEQ                       equ     00015h    ; _WRSEQ — sequential write 128-byte record
BDOS_FMAKE                       equ     00016h    ; _FMAKE — create new file via FCB
BDOS_SETDTA                      equ     0001Ah    ; _SETDTA — set disk transfer address (DE points to DTA)
BIOS_STREND                      equ     0F6C6h    ; BASIC String storage start (end of arrays)
BIOS_FILNAM                      equ     0F866h    ; primary filename buffer (11 bytes; used by BSAVE/BLOAD)
BIOS_FILNM2                      equ     0F871h    ; comparison filename buffer (11 bytes)
BIOS_HKEYI                       equ     0FD9Ah    ; Interrupt-handler hook (5 bytes; HKEYI in redbook §)
BIOS_HTIMI                       equ     0FD9Fh    ; Timer-interrupt (VBLANK) hook (5 bytes; HTIMI in redbook)
BIOS_HKEYC                       equ     0FDCCh    ; Keyboard-decoder hook (5 bytes) — nulled with `ret` by cart
BIOS_HFILE                       equ     0FE7Bh    ; BASIC FILES-statement hook (5 bytes; used by MEGA_PCMD_FILES)
BIOS_HOUTD                       equ     0FEE4h    ; OUTDO (printer/screen) output hook (5 bytes) — patched for breakpoints
BIOS_PROCNM                      equ     0FD89h    ; 16-byte buffer holding the BASIC `CALL <name>` symbol
BIOS_RG17SA                      equ     0FFF0h    ; Mirror of VDP register 17 — Mega-Assembler reuses bit 0 as a grey-mode flag
BIOS_SUBSLOT_REG                 equ     0FFFFh    ; MSX secondary-slot select register (1's complement encoding)
PORT_PPI_B                       equ     000A9h    ; PPI register B — keyboard matrix row input
PORT_PPI_C                       equ     000AAh    ; PPI register C — keyboard row select + CAPS LED + cassette
ID_HEADER_BINARY                 equ     000D0h    ; binary file marker — followed by start/end/exec words
ID_HEADER_BASIC                  equ     000D3h    ; tokenised BASIC program marker
ID_HEADER_ASCII                  equ     000EAh    ; ASCII source file marker
Z80_RET                          equ     000C9h    ; RET
Z80_JP                           equ     000C3h    ; JP nn
Z80_RLCA                         equ     00007h    ; rlca
Z80_RRCA                         equ     0000Fh    ; rrca
Z80_RLA                          equ     00017h    ; rla
Z80_RRA                          equ     0001Fh    ; rra
Z80_DAA                          equ     00027h    ; daa
Z80_CPL                          equ     0002Fh    ; cpl
Z80_SCF                          equ     00037h    ; scf
Z80_CCF                          equ     0003Fh    ; ccf
Z80_HALT                         equ     00076h    ; halt
Z80_EXX                          equ     000D9h    ; exx
Z80_DI                           equ     000F3h    ; di
Z80_EI                           equ     000FBh    ; ei
Z80_JR                           equ     00018h    ; JR e
Z80_JP_HL                        equ     000E9h    ; JP (HL)
Z80_CB_PREFIX                    equ     000CBh    ; CB-prefix marker — first byte of bit/shift/rotate group
Z80_ED_PREFIX                    equ     000EDh    ; ED-prefix marker — first byte of extended group
Z80_DD_PREFIX                    equ     000DDh    ; DD-prefix marker — IX-as-HL family
Z80_FD_PREFIX                    equ     000FDh    ; FD-prefix marker — IY-as-HL family
Z80_NEG                          equ     00044h    ; neg (ED 44)
Z80_RETN                         equ     00045h    ; retn (ED 45)
Z80_RETI                         equ     0004Dh    ; reti (ED 4D)
Z80_RRD                          equ     00067h    ; rrd (ED 67)
Z80_RLD                          equ     0006Fh    ; rld (ED 6F)
Z80_LDI                          equ     000A0h    ; ldi (ED A0)
Z80_CPI                          equ     000A1h    ; cpi (ED A1)
Z80_INI                          equ     000A2h    ; ini (ED A2)
Z80_OUTI                         equ     000A3h    ; outi (ED A3)
Z80_LDD                          equ     000A8h    ; ldd (ED A8)
Z80_CPD                          equ     000A9h    ; cpd (ED A9)
Z80_IND                          equ     000AAh    ; ind (ED AA)
Z80_OUTD                         equ     000ABh    ; outd (ED AB)
Z80_LDIR                         equ     000B0h    ; ldir (ED B0)
Z80_CPIR                         equ     000B1h    ; cpir (ED B1)
Z80_INIR                         equ     000B2h    ; inir (ED B2)
Z80_OTIR                         equ     000B3h    ; otir (ED B3)
Z80_LDDR                         equ     000B8h    ; lddr (ED B8)
Z80_CPDR                         equ     000B9h    ; cpdr (ED B9)
Z80_INDR                         equ     000BAh    ; indr (ED BA)
Z80_OTDR                         equ     000BBh    ; otdr (ED BB)
ID_NONE                          equ     00000h    ; no operands
ID_R_LOW                         equ     00001h    ; single 8-bit reg from low bits (AND r, OR r, …)
ID_R_LOW_PAREN_C                 equ     00002h    ; r,(C)        — ED IN r,(C)
ID_PAREN_C_R_LOW                 equ     00003h    ; (C),r        — ED OUT (C),r
ID_R_MID                         equ     00004h    ; single 16-bit RP (INC rp, DEC rp)
ID_BIT_R                         equ     00005h    ; bit-index, r — CB BIT/RES/SET b,r
ID_R_HL_LOW                      equ     00006h    ; single r/(HL) — INC r, DEC r
ID_HL_R_MID                      equ     00007h    ; HL, RP       — ADC HL,rp / SBC HL,rp (ED)
ID_RP_R_MID                      equ     00008h    ; RP, RP       — ADD HL,rp
ID_R_R                           equ     00009h    ; r, r'        — LD r,r'
ID_AF_AF                         equ     0000Ah    ; AF, AF'      — EX AF,AF'
ID_RST                           equ     0000Bh    ; RST vector   — RST p
ID_A_R                           equ     0000Ch    ; A, r         — ADC/ADD/SBC A,r
ID_IM_0                          equ     0000Dh    ; IM 0
ID_IM_1                          equ     0000Eh    ; IM 1
ID_IM_2                          equ     0000Fh    ; IM 2
ID_SP_HL                         equ     00010h    ; SP, HL       — LD SP,HL
ID_PAREN_R_A                     equ     00011h    ; (BC)/(DE), A — LD (BC),A / LD (DE),A
ID_A_PAREN_R                     equ     00012h    ; A, (BC)/(DE) — LD A,(BC) / LD A,(DE)
ID_A_IR                          equ     00013h    ; A, I or R    — LD A,I / LD A,R
ID_IR_A                          equ     00014h    ; I or R, A    — LD I,A / LD R,A
ID_PAREN_HL                      equ     00015h    ; (HL)         — JP (HL) / JP (IX) / JP (IY)
ID_RP_STACK                      equ     00016h    ; rp           — PUSH rp / POP rp
ID_RET_CC                        equ     00017h    ; cc           — RET cc
ID_DE_HL                         equ     00018h    ; DE, HL       — EX DE,HL
ID_PAREN_SP_HL                   equ     00019h    ; (SP), HL     — EX (SP),HL
ID_A_PAREN_N                     equ     0001Ah    ; A, (n)       — IN A,(n)
ID_PAREN_N_A                     equ     0001Bh    ; (n), A       — OUT (n),A
ID_N                             equ     0001Ch    ; n            — AND n / OR n / XOR n / CP n / SUB n
ID_A_N                           equ     0001Dh    ; A, n         — ADC A,n / ADD A,n / SBC A,n
ID_R_N                           equ     0001Eh    ; r, n         — LD r,n
ID_RP_NN                         equ     0001Fh    ; rp, nn       — LD rp,nn
ID_CC_E                          equ     00020h    ; cc, e        — JR cc,e
ID_E                             equ     00021h    ; e            — JR e / DJNZ e
ID_CC_NN                         equ     00022h    ; cc, nn       — JP cc,nn / CALL cc,nn
ID_NN                            equ     00023h    ; nn           — JP nn / CALL nn
ID_A_PAREN_NN                    equ     00024h    ; A, (nn)      — LD A,(nn)
ID_PAREN_NN_A                    equ     00025h    ; (nn), A      — LD (nn),A
ID_RP_PAREN_NN                   equ     00026h    ; rp, (nn)     — LD HL,(nn)
ID_PAREN_NN_RP                   equ     00027h    ; (nn), rp     — LD (nn),HL
ID_RP_PAREN_NN_ED                equ     00028h    ; rp, (nn) ED  — LD rp,(nn) (ED prefix)
ID_PAREN_NN_RP_ED                equ     00029h    ; (nn), rp ED  — LD (nn),rp (ED prefix)
ID_OPERAND_A                     equ     00007h    ; "A"  — 8-bit reg name
ID_OPERAND_DE                    equ     0000Ah    ; "DE" — 16-bit RP name
ID_OPERAND_HL                    equ     0000Ch    ; "HL"
ID_OPERAND_SP                    equ     0000Eh    ; "SP"
ID_OPERAND_AF                    equ     00020h    ; "AF"
ID_OPERAND_PAREN_C               equ     00026h    ; "(C)" — ED IN/OUT (C)
ID_OPERAND_IX                    equ     00016h    ; "IX" — DD-prefix index reg tag (DISASM_DD_PREFIX at 621A)
ID_OPERAND_IY                    equ     00018h    ; "IY" — FD-prefix index reg tag (DISASM_FD_PREFIX at 621D)
ID_ARGUMENT_I                    equ     00010h    ; "I"  (ARGUMENT_IR)
ID_ARGUMENT_R                    equ     00020h    ; "R"  (ARGUMENT_IR)
ID_ARGUMENT_B                    equ     00080h    ; "B"  (ARGUMENT_R8)
ID_ARGUMENT_C                    equ     00088h    ; "C"  (ARGUMENT_R8)
ID_ARGUMENT_D                    equ     00090h    ; "D"  (ARGUMENT_R8)
ID_ARGUMENT_E                    equ     00098h    ; "E"  (ARGUMENT_R8)
ID_ARGUMENT_H                    equ     000A0h    ; "H" (ARGUMENT_R8)
ID_ARGUMENT_L                    equ     000A8h    ; "L" (ARGUMENT_R8)
ID_ARGUMENT_A                    equ     000B8h    ; "A" (ARGUMENT_R8)
ID_ARGUMENT_BC                   equ     000C0h    ; "BC" (ARGUMENT_BC_DE); +1 = "(BC)"
ID_ARGUMENT_DE                   equ     000D0h    ; "DE" (ARGUMENT_BC_DE); +1 = "(DE)"
ID_ARGUMENT_HL                   equ     000E0h    ; "HL" (ARGUMENT_HL);    +1 = "(HL)"
ID_ARGUMENT_IX                   equ     000E4h    ; "IX" (ARGUMENT_IX)
ID_ARGUMENT_IY                   equ     000E6h    ; "IY" (ARGUMENT_IY)
ID_ARGUMENT_SP                   equ     000F0h    ; "SP" (ARGUMENT_SP);    +1 = "(SP)"
ID_ARGUMENT_AF                   equ     000F8h    ; "AF" (ARGUMENT_AF)
ID_ARGUMENT_LITERAL              equ     00030h    ; numeric literal (no register); +1 = "(n)" or "(nn)"
ID_ARGUMENT_COND_NZ              equ     00040h    ; NZ
ID_ARGUMENT_COND_Z               equ     00048h    ; Z
ID_ARGUMENT_COND_NC              equ     00050h    ; NC
ID_ARGUMENT_COND_PO              equ     00060h    ; PO
ID_ARGUMENT_COND_PE              equ     00068h    ; PE
ID_ARGUMENT_COND_P               equ     00070h    ; P
ID_ARGUMENT_COND_M               equ     00078h    ; M
ID_ASM_PLAIN                     equ     00000h    ; no operand (CCF/CPL/DI/EI/EXX/HALT/NOP/RLA/...)
ID_ASM_ED                        equ     00001h    ; ED-prefix no-operand (CPD/CPI/IND/INI/LDD/LDI/NEG/RETI/...)
ID_ASM_ARITH_A                   equ     00002h    ; 8-bit A-arith with n or r operand (AND/CP/OR/SUB/XOR)
ID_ASM_INC_DEC                   equ     00003h    ; INC/DEC — r or rp
ID_ASM_BIT                       equ     00004h    ; CB-prefix bit ops (BIT/RES/SET b,r)
ID_ASM_SHIFT                     equ     00005h    ; CB-prefix shift/rotate (RL/RLC/RR/RRC/SLA/SRA/SRL r)
ID_ASM_ADC_SBC                   equ     00006h    ; ADC/SBC — A,n / A,r / HL,rp
ID_ASM_ADD                       equ     00007h    ; ADD — A,n / A,r / HL,rp / IX,rp / IY,rp
ID_ASM_LD                        equ     00008h    ; LD — the entire LD family
ID_ASM_CALL                      equ     00009h    ; CALL nn / CALL cc,nn
ID_ASM_JP                        equ     0000Ah    ; JP nn / JP cc,nn / JP (HL)/(IX)/(IY)
ID_ASM_JR                        equ     0000Bh    ; JR e / JR cc,e
ID_ASM_DJNZ                      equ     0000Ch    ; DJNZ e
ID_ASM_RET                       equ     0000Dh    ; RET / RET cc
ID_ASM_EX                        equ     0000Eh    ; EX DE,HL / EX AF,AF' / EX (SP),HL/IX/IY
ID_ASM_IM                        equ     0000Fh    ; IM 0 / IM 1 / IM 2
ID_ASM_IN                        equ     00010h    ; IN A,(n) / IN r,(C)
ID_ASM_OUT                       equ     00011h    ; OUT (n),A / OUT (C),r
ID_ASM_PUSH_POP                  equ     00012h    ; PUSH rp / POP rp
ID_ASM_RST                       equ     00013h    ; RST p
ID_ASM_ORG                       equ     00014h    ; ORG nn pseudo-op
ID_ASM_END                       equ     00015h    ; END pseudo-op
ID_ASM_DEFS                      equ     00016h    ; DEFS n / DS n
ID_ASM_EQU                       equ     00017h    ; LABEL EQU value
ID_ASM_DEFW                      equ     0001Eh    ; DEFW / DW (high opt_type — different path at 5358)
ID_ASM_DEFB                      equ     0001Fh    ; DEFB / DEFM / DB (also high path)
Z80_NOP                          equ     00000h    ; NOP
Z80_LD_RP_NN                     equ     00001h    ; LD rp,nn (base — rp in bits 4-5)
Z80_LD_PAREN_BC_A                equ     00002h    ; LD (BC),A   (base — mask EF includes DE form)
Z80_INC_RP                       equ     00003h    ; INC rp (base)
Z80_INC_R                        equ     00004h    ; INC r  (base — r in bits 3-5)
Z80_DEC_R                        equ     00005h    ; DEC r  (base)
Z80_LD_R_N                       equ     00006h    ; LD r,n (base — r in bits 3-5)
Z80_EX_AF_AF                     equ     00008h    ; EX AF,AF'
Z80_ADD_HL_RP                    equ     00009h    ; ADD HL,rp (base)
Z80_LD_A_PAREN_BC                equ     0000Ah    ; LD A,(BC)  (mask EF includes DE form)
Z80_LD_A_PAREN_DE                equ     0001Ah    ; LD A,(DE)
Z80_DEC_RP                       equ     0000Bh    ; DEC rp (base)
Z80_DJNZ                         equ     00010h    ; DJNZ e
Z80_JR_CC                        equ     00020h    ; JR cc,e (base — cc in bits 3-4)
Z80_LD_PAREN_NN_HL               equ     00022h    ; LD (nn),HL
Z80_LD_HL_PAREN_NN               equ     0002Ah    ; LD HL,(nn)
Z80_LD_PAREN_NN_A                equ     00032h    ; LD (nn),A
Z80_LD_A_PAREN_NN                equ     0003Ah    ; LD A,(nn)
Z80_LD_R_R                       equ     00040h    ; LD r,r' (base — mask C0)
Z80_ADD_A_R                      equ     00080h    ; ADD A,r (base — mask F8)
Z80_ADC_A_R                      equ     00088h    ; ADC A,r (base)
Z80_SUB_R                        equ     00090h    ; SUB r   (base)
Z80_SBC_A_R                      equ     00098h    ; SBC A,r (base)
Z80_AND_R                        equ     000A0h    ; AND r   (base)
Z80_XOR_R                        equ     000A8h    ; XOR r   (base)
Z80_OR_R                         equ     000B0h    ; OR r    (base)
Z80_CP_R                         equ     000B8h    ; CP r    (base)
Z80_RET_CC                       equ     000C0h    ; RET cc  (base — cc in bits 3-5)
Z80_POP_RP                       equ     000C1h    ; POP rp  (base)
Z80_JP_CC                        equ     000C2h    ; JP cc,nn (base)
Z80_CALL_CC                      equ     000C4h    ; CALL cc,nn (base)
Z80_PUSH_RP                      equ     000C5h    ; PUSH rp (base)
Z80_ADD_A_N                      equ     000C6h    ; ADD A,n
Z80_RST                          equ     000C7h    ; RST p   (base — p in bits 3-5)
Z80_RST_18                       equ     000DFh    ; RST 18h (also used as "disarmed breakpoint" sentinel)
CHAR_BS                          equ     00008h    ; ASCII backspace (used by M command edit-back navigation)
Z80_CALL                         equ     000CDh    ; CALL nn
Z80_ADC_A_N                      equ     000CEh    ; ADC A,n
Z80_OUT_N_A                      equ     000D3h    ; OUT (n),A
Z80_SUB_N                        equ     000D6h    ; SUB n
Z80_SBC_A_N                      equ     000DEh    ; SBC A,n
Z80_IN_A_N                       equ     000DBh    ; IN A,(n)
Z80_EX_SP_HL                     equ     000E3h    ; EX (SP),HL
Z80_AND_N                        equ     000E6h    ; AND n
Z80_EX_DE_HL                     equ     000EBh    ; EX DE,HL
Z80_XOR_N                        equ     000EEh    ; XOR n
Z80_OR_N                         equ     000F6h    ; OR n
Z80_LD_SP_HL                     equ     000F9h    ; LD SP,HL
Z80_CP_N                         equ     000FEh    ; CP n
Z80_BIT_BASE                     equ     00040h    ; BIT b,r  (mask C0, b in bits 3-5, r in bits 0-2)
Z80_RES_BASE                     equ     00080h    ; RES b,r
Z80_SET_BASE                     equ     000C0h    ; SET b,r
Z80_RLC_BASE                     equ     00000h    ; RLC r    (mask F8, r in bits 0-2)
Z80_RRC_BASE                     equ     00008h    ; RRC r
Z80_RL_BASE                      equ     00010h    ; RL r
Z80_RR_BASE                      equ     00018h    ; RR r
Z80_SLA_BASE                     equ     00020h    ; SLA r
Z80_SRA_BASE                     equ     00028h    ; SRA r
Z80_SRL_BASE                     equ     00038h    ; SRL r
Z80_SBC_HL_BASE                  equ     00042h    ; SBC HL,rp  (ED 42 base; mask CF, rp in bits 4-5)
Z80_IM_0_OPC                     equ     00046h    ; IM 0       (ED 46)
Z80_IM_1_OPC                     equ     00056h    ; IM 1       (ED 56)
Z80_IM_2_OPC                     equ     0005Eh    ; IM 2       (ED 5E)
Z80_ADC_HL_BASE                  equ     0004Ah    ; ADC HL,rp  (ED 4A base)
Z80_LD_PNN_RP_BASE               equ     00043h    ; LD (nn),rp (ED 43 base; mask CF)
Z80_LD_RP_PNN_BASE               equ     0004Bh    ; LD rp,(nn) (ED 4B base)
Z80_LD_IR_A_BASE                 equ     00047h    ; LD I/R,A   (ED 47 / 4F; mask F7, bit 3 → I vs R)
Z80_LD_A_IR_BASE                 equ     00057h    ; LD A,I/R   (ED 57 / 5F; mask F7)
Z80_LD_A_R                       equ     0005Fh    ; LD A,R     (ED 5F; alt to Z80_LD_A_IR_BASE)
Z80_OUT_C_R_BASE                 equ     00041h    ; OUT (C),r  (ED 41 base; mask C7, r in bits 3-5)
Z80_IN_R_C_BASE                  equ     00040h    ; IN r,(C)   (ED 40 base) — shadows main Z80_LD_R_R via [code]
Z80_ADD_HL_BC                    equ     00009h    ; ADD HL,BC (collides with Z80_ADD_HL_RP base)
Z80_ADD_HL_DE                    equ     00019h    ; ADD HL,DE
Z80_LD_HL_NN                     equ     00021h    ; LD HL,nn
Z80_INC_HL                       equ     00023h    ; INC HL
Z80_ADD_HL_HL                    equ     00029h    ; ADD HL,HL
Z80_DEC_HL                       equ     0002Bh    ; DEC HL
Z80_INC_PAREN_HL                 equ     00034h    ; INC (HL)
Z80_DEC_PAREN_HL                 equ     00035h    ; DEC (HL)
Z80_LD_PAREN_HL_N                equ     00036h    ; LD (HL),n
Z80_ADD_HL_SP                    equ     00039h    ; ADD HL,SP
Z80_LD_B_PAREN_HL                equ     00046h    ; LD B,(HL)
Z80_LD_C_PAREN_HL                equ     0004Eh    ; LD C,(HL)
Z80_LD_D_PAREN_HL                equ     00056h    ; LD D,(HL)
Z80_LD_E_PAREN_HL                equ     0005Eh    ; LD E,(HL)
Z80_LD_H_PAREN_HL                equ     00066h    ; LD H,(HL)
Z80_LD_L_PAREN_HL                equ     0006Eh    ; LD L,(HL)
Z80_LD_PAREN_HL_B                equ     00070h    ; LD (HL),B
Z80_LD_PAREN_HL_C                equ     00071h    ; LD (HL),C
Z80_LD_PAREN_HL_D                equ     00072h    ; LD (HL),D
Z80_LD_PAREN_HL_E                equ     00073h    ; LD (HL),E
Z80_LD_PAREN_HL_H                equ     00074h    ; LD (HL),H
Z80_LD_PAREN_HL_L                equ     00075h    ; LD (HL),L
Z80_LD_PAREN_HL_A                equ     00077h    ; LD (HL),A
Z80_LD_A_PAREN_HL                equ     0007Eh    ; LD A,(HL)
Z80_ADD_A_PAREN_HL               equ     00086h    ; ADD A,(HL)
Z80_ADC_A_PAREN_HL               equ     0008Eh    ; ADC A,(HL)
Z80_SUB_PAREN_HL                 equ     00096h    ; SUB (HL)
Z80_SBC_A_PAREN_HL               equ     0009Eh    ; SBC A,(HL)
Z80_AND_PAREN_HL                 equ     000A6h    ; AND (HL)
Z80_XOR_PAREN_HL                 equ     000AEh    ; XOR (HL)
Z80_OR_PAREN_HL                  equ     000B6h    ; OR (HL)
Z80_CP_PAREN_HL                  equ     000BEh    ; CP (HL)
Z80_POP_HL                       equ     000E1h    ; POP HL
Z80_PUSH_HL                      equ     000E5h    ; PUSH HL
Z80_PSEUDO_OP                    equ     00000h    ; Filler byte for assembler-pseudo-op MNEMONIC records (DB/DW/DS/EQU/END/ORG)
ARGUMENT_R8                      equ     00081h    ; 8-bit r-table register: B/C/D/E/H/L/A
ARGUMENT_IR                      equ     00080h    ; I or R (interrupt / refresh special 8-bit)
ARGUMENT_BC_DE                   equ     000BEh    ; 16-bit RP pair BC or DE (rp-field in bits 4-5)
ARGUMENT_HL                      equ     000B2h    ; 16-bit HL (special — separate code path from BC/DE)
ARGUMENT_SP                      equ     0009Eh    ; 16-bit SP (special — only valid as RP in `inc/dec/add` forms)
ARGUMENT_AF                      equ     000A0h    ; AF (only valid in PUSH/POP)
ARGUMENT_IX                      equ     000B4h    ; IX (always emitted with DD prefix)
ARGUMENT_IY                      equ     000B8h    ; IY (always emitted with FD prefix)
ARGUMENT_COND                    equ     000C0h    ; Z80 condition code (NZ/Z/NC/C/PO/PE/P/M) for jp/jr/call/ret cc
BIOS_RDSLT                       equ     0000Ch    ; Read RAM byte in any slot
BIOS_WRSLT                       equ     00014h    ; Write RAM byte in any slot
BIOS_WRTVDP                      equ     00047h    ; Write to any VDP register
BIOS_RDVRM                       equ     0004Ah    ; Read byte from VRAM
BIOS_WRTVRM                      equ     0004Dh    ; Write byte to VRAM
BIOS_SETWRT                      equ     00053h    ; Prime VDP for VRAM write at HL
BIOS_FILVRM                      equ     00056h    ; Fill VRAM region with a byte
BIOS_LDIRMV                      equ     00059h    ; Block copy VRAM → main memory
BIOS_LDIRVM                      equ     0005Ch    ; Block copy main memory → VRAM
BIOS_INITXT                      equ     0006Ch    ; Initialize VDP to 40×24 text mode
BIOS_INIT32                      equ     0006Fh    ; Initialize VDP to 32×24 text mode (SCREEN 1)
BIOS_INIGRP                      equ     00072h    ; Initialize VDP to graphics mode
BIOS_CALPAT                      equ     00084h    ; Compute sprite-pattern table entry address
BIOS_CALATR                      equ     00087h    ; Compute sprite-attribute table entry address
BIOS_GRPPRT                      equ     0008Dh    ; Print character on graphic screen
BIOS_CHSNS                       equ     0009Ch    ; Sense keyboard buffer for any pending character
BIOS_CHGET                       equ     0009Fh    ; Get character from keyboard buffer (blocks)
BIOS_CHPUT                       equ     000A2h    ; Output character A to current screen device
BIOS_LPTOUT                      equ     000A5h    ; Printer character output
BIOS_PINLIN                      equ     000AEh    ; Read a line from the console editor
BIOS_BREAKX                      equ     000B7h    ; Check CTRL-STOP directly (does not go through hook)
BIOS_POSIT                       equ     000C6h    ; Set cursor position (H=row, L=col)
BIOS_TAPION                      equ     000E1h    ; Cassette: read header (turn motor on)
BIOS_TAPIN                       equ     000E4h    ; Cassette: read one byte
BIOS_TAPIOF                      equ     000E7h    ; Cassette: end of read (motor off)
BIOS_TAPOON                      equ     000EAh    ; Cassette: write header (turn motor on)
BIOS_TAPOUT                      equ     000EDh    ; Cassette: write one byte
BIOS_TAPOOF                      equ     000F0h    ; Cassette: end of write (motor off)
BIOS_CHGCAP                      equ     00132h    ; Toggle CAPS-Lock LED (A=0 off, A=1 on)
BIOS_PHYDIO                      equ     00144h    ; Disk-BIOS hook (no-op without disk ROM)
BIOS_CALBAS                      equ     00159h    ; Call into BASIC from any slot
BIOS_CLEAR_SCREEN                equ     00777h    ; Internal BIOS clear-screen routine (not on the jump table; version-specific)
BIOS_BEEP                        equ     01113h    ; Beep routine (internal BIOS entry, not the documented 00C0h jump-table version)
BIOS_EVAL_BASIC_OPERAND          equ     0542Fh    ; BASIC routine: evaluate next operand into DE (call via BIOS_CALBAS, IX=here)
BIOS_BASIC_ERROR_HANDLER         equ     0406Fh    ; BASIC routine: raise error with code in E (call via BIOS_CALBAS, IX=here)

        ; BASIC_CMD name, handler
        ; Emit a full name→handler record in BASIC_CMD_TABLE / MEGA_PCMD_TABLE.
        ; `name` must be passed as a sjasmplus `"…"C` literal so the assembler
        ; ORs bit 7 into the last char as the terminator. Followed by the
        ; 2-byte LE handler pointer.
        macro BASIC_CMD name, handler
                db      name
                dw      handler
        endm

        ; MEGA_CMD name, handler
        ; Emit a full name→handler record in MEGA_PCMD_TABLE — the
        ; assembler's `>` prompt dispatcher. Structurally identical
        ; to BASIC_CMD (same byte layout walked by the same PCMD_LOOKUP
        ; code), but tagged separately because these are MEGA's own
        ; prompt commands, not BASIC `CALL <name>` extensions.
        macro MEGA_CMD name, handler
                db      name
                dw      handler
        endm

        ; DISASM_SIMPLE opcode, name
        ; Emit a record of a no-operand DISASM_TABLE entry: 1-byte opcode
        ; followed by the mnemonic name as a sjasmplus `"…"C` literal (last
        ; char ORed with 80h as terminator). Only works for the clean records
        ; whose format is exactly opcode+name (no operand-info bytes).
        macro DISASM_SIMPLE opcode, name
                db      opcode, name
        endm

        ; MNEMONIC head, tail, opt_type, opcode
        ; Emit one full record of a per-letter MNEMONIC_TABLE: the suffix
        ; chars (`tail`, no bit-7 termination — the marker terminates the
        ; name walk), then the operand-type marker `opt_type | 80h`, then
        ; the 1-byte opcode. `head` is the implied first letter (the
        ; table's letter) — documentation only, NOT emitted; the full
        ; mnemonic name is `head`+`tail`. Use ID_ASM_* for opt_type and
        ; Z80_* for opcode so the table reads like a Z80 reference card.
        macro MNEMONIC head, tail, opt_type, opcode
                db      tail
                db      opt_type | 80h
                db      opcode
        endm

        ; DISASM mask, op, type
        ; One record of DISASM_TABLE_*'s operand-form sub-tables. The
        ; walker at 62F1 reads <mask> <op> <type> triples: when
        ; `(user_opcode & mask) == op`, returns `type` — an index into
        ; DISASM_OPERAND_TABLE that picks the (op1, op2) operand-encoder
        ; pair. Use the ID_* equates for `type` (ID_R_R, ID_R_N, …).
        ; Records are grouped by mnemonic; the group ends with the
        ; bit-7-terminated mnemonic name (use a plain `db "NAME"C`).
        macro DISASM mask, op, type
                db      mask, op, type
        endm

        ; OVERLAP_LD_DE
        ; Emit the single byte 0x11 — the opcode of `ld de,nn`. Used in
        ; the multi-entry-point operand emitters (OP_DIGIT_0/1/2,
        ; OP_SP/AF/DE/HL/A). Entering at offset+0 executes the byte as
        ; the start of an "ld de,(...)" that absorbs the next two bytes
        ; (a harmless DE-clobber); entering at offset+1 instead executes
        ; the next two bytes as the actual `ld a,nn` for that alt entry.
        ; Labels at offset+1 of each block tag the alternate entries.
        macro OVERLAP_LD_DE
                db      11h
        endm

        ; OVERLAP_LD_BC
        ; Emit the single byte 0x01 — the opcode of `ld bc,nn`. The
        ; DD/FD prefix dispatch uses this once: the bytes at 621C
        ; (01 3E 18) decode as `ld bc,183Eh` when entered from DD at
        ; 621A (a harmless BC-clobber), or as `ld a,18h` when entered
        ; from FD at 621D (the IY alt entry). Same trick as
        ; OVERLAP_LD_DE, but the absorber is a 3-byte `ld bc,nnnn`.
        macro OVERLAP_LD_BC
                db      1
        endm

        ; OVERLAP_LD_HL
        ; Emit the single byte 0x21 — the opcode of `ld hl,nn`. Used
        ; by ASM_ERROR_NO_MNEMONIC/OPERAND/RAISE (5BB6/5BB9/5BBC) to
        ; pack three `ld a,nn` entry points (A=08/10h/20h, picking
        ; which error bit to set in (ix+2)) into 8 bytes that share
        ; the same tail body. Each absorber decodes as `ld hl,nnnn`
        ; on the falling-through entry and as `ld a,nn` on the next
        ; alt entry — same trick as OVERLAP_LD_DE.
        macro OVERLAP_LD_HL
                db      21h
        endm

        ; OVERLAP_LD_A
        ; Emit the single byte 0x3E — the opcode of `ld a,nn`. Used at
        ; 42DD to pack two entries: the primary entry runs
        ; `ld a,0AFh` (a setup load before TAPOON), the alt entry at
        ; 42DE (BIOS_TAPOON_PRESERVE) executes the AFh byte as `xor a`
        ; instead — sharing the same TAPOON-wrapper body that follows.
        macro OVERLAP_LD_A
                db      3Eh
        endm

        ; OVERLAP_CP
        ; Emit the single byte 0xFE — the opcode of `cp n`. Used at
        ; 5934 so an upstream fall-through executes `cp 0C0h` while
        ; the dispatch entry ASM_EMIT_OP_SHIFT at 5935 sees the C0h
        ; byte alone as `ret nz` (the standard ret-if-not-final guard
        ; shared by every ASM_EMIT_OP_* dispatch slot).
        macro OVERLAP_CP
                db      0FEh
        endm

        ; ASM_REG name, type, mask
        ; One record of ASM_REG_NAME_TABLE: 2-char ASCII name (use trailing
        ; space for 1-letter regs like "B ") + register-family type code
        ; + bit-positioned encoding mask.
        ; `name` is exactly 2 ASCII bytes — pad with space for one-letter
        ;   regs (e.g. "B ") so each record is the fixed 4-byte stride.
        ; `type` (returned in B with bit 7 stripped by ASM_LOOKUP_REG_NAME)
        ;   identifies the register family — use one of ARGUMENT_R8 /
        ;   ARGUMENT_IR / ARGUMENT_BC_DE / ARGUMENT_HL / ARGUMENT_SP /
        ;   ARGUMENT_AF / ARGUMENT_IX / ARGUMENT_IY / ARGUMENT_COND. Each
        ;   constant already has bit 7 set so the walker treats the byte
        ;   as a valid entry marker.
        ; `mask` is the register-specific encoding pre-shifted into its
        ;   opcode field (8-bit regs: r-field in bits 3-5; 16-bit RPs:
        ;   rp-field in bits 4-5; cond codes: cc-field in bits 3-5). Bits
        ;   1-2 also OR into MEGA_ASM_OPC_FLAGS as the matched-family
        ;   fingerprint.
        macro ASM_REG name, type, mask
                db      name, type, mask
        endm

ROM_HEADER:
        ; MSX cartridge header (magic, INIT, STATEMENT, DEVICE, TEXT)
        ; MSX cartridge header (redbook §1).
        ; 4000-4001  "AB" magic so the BIOS recognises a cartridge in the slot.
        ; 4002-4003  INIT — entered by the BIOS during slot scan after RAM is up.
        ; 4004-4005  STATEMENT — called by BASIC interpreter for `CALL <name>` syntax.
        ; 4006-4007  DEVICE — handler for cassette/device extension (unused here).
        ; 4008-4009  TEXT — pointer to a BASIC text program autostarted at boot (unused).
        ; 400A-400F  Reserved (must be zero).
        db      "AB"                                           ;#4000: 41 42
        dw      MEGA_INIT                                      ;#4002: 37 40
        dw      BASIC_STATEMENT                                ;#4004: 30 6C
        dw      0                                              ;#4006: 00 00
        dw      0                                              ;#4008: 00 00
        dw      0                                              ;#400A: 00 00
        dw      0                                              ;#400C: 00 00
        dw      0                                              ;#400E: 00 00

MEGA_RESUME:
        ; Warm-restart vector — `JP MEGA_PROMPT_LOOP` to drop into the assembler prompt
        jp      MEGA_PROMPT_LOOP                               ;#4010: C3 12 41

MEGA_CMD_ASM:
        ; `CALL ASM` handler (C=0); falls into MEGA_INIT_PREP for a light re-init
        ld      c,0                                            ;#4013: 0E 00
        jr      MEGA_INIT_PREP                                 ;#4015: 18 02

MEGA_CMD_START:
        ; `CALL START` handler (C=1); falls into MEGA_INIT_PREP for a full init
        ld      c,1                                            ;#4017: 0E 01
MEGA_INIT_PREP:
        ; Shared body — saves BIOS_DIRBUF pointer to ECC1h, lowers it to SP-300h
        ; Saves the BIOS_DIRBUF cell (F351h) into MEGA_DIRBUF_SAV (ECC1h),
        ; then computes SP-300h (the `ld hl,FD00h ; add hl,sp` trick — FD00h
        ; is -300h in 16-bit two's complement) and writes that back to F351h.
        ; F351h serves Disk BASIC as the "lowest safe RAM" pointer / sector
        ; buffer for `DSKI$` and `DSKO$`, so by lowering it 768 bytes below
        ; the current SP the cart claims those 768 bytes for its scratch /
        ; resident-driver use without disturbing whatever's above SP. The
        ; original DIRBUF pointer is restored on exit via
        ; MEGA_RETURN_TO_BASIC so subsequent `DSKI$`/`DSKO$` calls remain
        ; valid. Concludes with `jr MEGA_INIT_BODY`.
        ld      hl,(BIOS_DIRBUF)                               ;#4019: 2A 51 F3
        ld      (MEGA_DIRBUF_SAV),hl                           ;#401C: 22 C1 EC
        ld      hl,0FD00h                                      ;#401F: 21 00 FD
        add     hl,sp                                          ;#4022: 39
        ld      (BIOS_DIRBUF),hl                               ;#4023: 22 51 F3
        call    INSTALL_HKEYC_NULL                             ;#4026: CD E7 7F
        jr      MEGA_INIT_BODY                                 ;#4029: 18 1E
        rept    12
        nop
        endr

MEGA_INIT:
        ; INIT entry — called by BIOS during slot scan to bring the cart online
        ; Slot-scan entry. Holding CTRL at boot (PPI port AAh selects keyboard row 6;
        ; `in a,(A9h)` reads it; row 6 bit 1 = CTRL — redbook line 3554, key 31h)
        ; skips cart initialisation — `ret z` bails before touching RAM. Otherwise the
        ; routine drops into MEGA_INIT_BODY at 4049h. The path that arrives through
        ; MEGA_INIT_PREP enters at MEGA_INIT_BODY directly, skipping the kbd test
        ; and the call to BIOS_INITXT that switches the VDP to 40×24 text
        ; mode. C controls a branch at 4052h: C=0 → patch RAM hooks at FA00/FA08
        ; with RETs only; C=1 → first copy 30h bytes of a hook template from 425Ah
        ; into FA00h and call the installer at 693Ch.
        ld      a,1                                            ;#4037: 3E 01
        ld      (BIOS_ENSTOP),a                                ;#4039: 32 B0 FB
        ld      a,16h                                          ;#403C: 3E 16
        out     (0AAh),a                                       ;#403E: D3 AA
        in      a,(0A9h)                                       ;#4040: DB A9
        bit     1,a                                            ;#4042: CB 4F
        ret     z                                              ;#4044: C8
        push    hl                                             ;#4045: E5
        call    BIOS_INITXT                                    ;#4046: CD 6C 00
MEGA_INIT_BODY:
        ; Mid-routine continuation joined by MEGA_INIT_PREP (skips kbd check)
        pop     hl                                             ;#4049: E1
        ld      (MEGA_SAVED_HL),hl                             ;#404A: 22 FA F9
        ld      (MEGA_SAVED_SP),sp                             ;#404D: ED 73 FC F9
        push    bc                                             ;#4051: C5
        dec     c                                              ;#4052: 0D
        jr      nz,MEGA_INIT_HOOK_CHECK                        ;#4053: 20 27
        ld      hl,SLOT_DRIVER_TEMPLATE_SRC                    ;#4055: 21 5A 42
        ld      de,MEGA_HOOK_FA00                              ;#4058: 11 00 FA
        ld      bc,INPUT_LINE_FROM_KBD-SLOT_DRIVER_TEMPLATE_SRC ;#405B: 01 30 00
        ldir                                                   ;#405E: ED B0
        call    MEGA_INSTALL_DRIVER                            ;#4060: CD 3C 69
        jr      c,MEGA_INIT_HOOK_DISABLE                       ;#4063: 38 0F
        ld      (MEGA_HOOK_SLOT_PATCH),a                       ;#4065: 32 03 FA
        ld      a,b                                            ;#4068: 78
        ld      (MEGA_HOOK_SUBSLOT_PATCH),a                    ;#4069: 32 0A FA
MEGA_INIT_NO_SLOTDRV:
        ; Skip-slot-driver path — set RAM range DE=1, HL=7FFFh, fall into INSTALL_BUFFERS
        ld      de,1                                           ;#406C: 11 01 00
        ld      hl,7FFFh                                       ;#406F: 21 FF 7F
        jr      MEGA_INSTALL_BUFFERS                           ;#4072: 18 1F

MEGA_INIT_HOOK_DISABLE:
        ; Slot-driver install failed — write Z80_RET into MEGA_HOOK_FA00/08
        ld      a,Z80_RET                                      ;#4074: 3E C9
        ld      (MEGA_HOOK_FA00),a                             ;#4076: 32 00 FA
        ld      (MEGA_HOOK_FA08),a                             ;#4079: 32 08 FA
MEGA_INIT_HOOK_CHECK:
        ; Inspect MEGA_HOOK_FA00 — if F3h (DI = already installed) use default RAM
        ld      a,(MEGA_HOOK_FA00)                             ;#407C: 3A 00 FA
        cp      Z80_DI                                         ;#407F: FE F3
        jr      z,MEGA_INIT_NO_SLOTDRV                         ;#4081: 28 E9
        ld      de,8100h                                       ;#4083: 11 00 81
        ld      hl,0CFFFh                                      ;#4086: 21 FF CF
        ld      a,(BIOS_BOTTOM+1)                              ;#4089: 3A 49 FC
        cp      0C0h                                           ;#408C: FE C0
        jr      c,MEGA_INSTALL_BUFFERS                         ;#408E: 38 03
        ld      de,DRIVER_INIT_SLOTS                           ;#4090: 11 00 C1
MEGA_INSTALL_BUFFERS:
        ; Store DE→MEGA_SRC_BUF_START and HL→MEGA_USER_CODE_END+SYM_TABLE_END etc.
        ld      (MEGA_SRC_BUF_START),de                        ;#4093: ED 53 01 EC
        ld      (MEGA_USER_CODE_END),hl                        ;#4097: 22 07 EC
        ld      (MEGA_SYM_TABLE_END),hl                        ;#409A: 22 4B EC
        dec     hl                                             ;#409D: 2B
        dec     hl                                             ;#409E: 2B
        ld      (MEGA_SRC_BUF_END),hl                          ;#409F: 22 05 EC
        ld      hl,0EBFFh                                      ;#40A2: 21 FF EB
        ld      (MEGA_USER_CODE_START),hl                      ;#40A5: 22 09 EC
        pop     bc                                             ;#40A8: C1
        dec     c                                              ;#40A9: 0D
        jr      nz,MEGA_INIT_BUF_VALIDATE                      ;#40AA: 20 18
        call    RESET_SOURCE_BUFFER                            ;#40AC: CD 44 49
        ld      a,"="                                          ;#40AF: 3E 3D
        ld      (MEGA_PAGE_HEIGHT),a                           ;#40B1: 32 00 EC
        ld      hl,0                                           ;#40B4: 21 00 00
        ld      (MEGA_LAST_MEM_ADDR),hl                        ;#40B7: 22 43 EC
        ld      (MEGA_DISASM_LAST_END),hl                      ;#40BA: 22 45 EC
        call    INIT_ASSEMBLER_STATE                           ;#40BD: CD FA 43
        xor     a                                              ;#40C0: AF
        ld      (MEGA_PCMD_C_MODE),a                           ;#40C1: 32 6D EC
MEGA_INIT_BUF_VALIDATE:
        ; Validate MEGA_SRC_BUF_HEAD lies inside [START,END] — reset buffer if not
        ld      hl,(MEGA_SRC_BUF_HEAD)                         ;#40C4: 2A 03 EC
        ld      de,(MEGA_SRC_BUF_START)                        ;#40C7: ED 5B 01 EC
        dec     de                                             ;#40CB: 1B
        call    COMPARE_HL_DE                                  ;#40CC: CD 98 50
        call    c,RESET_SOURCE_BUFFER                          ;#40CF: DC 44 49
        ex      de,hl                                          ;#40D2: EB
        ld      hl,(MEGA_SRC_BUF_END)                          ;#40D3: 2A 05 EC
        call    COMPARE_HL_DE                                  ;#40D6: CD 98 50
        call    c,RESET_SOURCE_BUFFER                          ;#40D9: DC 44 49
        ld      a,0FFh                                         ;#40DC: 3E FF
        ld      (BIOS_CAPST),a                                 ;#40DE: 32 AB FC
        ld      a,0                                            ;#40E1: 3E 00
        call    BIOS_CHGCAP                                    ;#40E3: CD 32 01
        ld      ix,MEGA_STATE_FLAGS                            ;#40E6: DD 21 F5 F9
        ld      (ix),0                                         ;#40EA: DD 36 00 00
        call    CLEAR_PASS1_DONE_FLAG                          ;#40EE: CD 4B 49
        call    PRINT_BANNER                                   ;#40F1: CD 00 6B
        ld      hl,BIOS_HOUTD                                  ;#40F4: 21 E4 FE
        ld      de,BIOS_HOUTD_PASSTHROUGH                      ;#40F7: 11 74 EC
        ld      bc,5                                           ;#40FA: 01 05 00
        ldir                                                   ;#40FD: ED B0
        ld      a,Z80_JP                                       ;#40FF: 3E C3
        ld      hl,HOUTD_HOOK                                  ;#4101: 21 6F 46
        ld      (BIOS_HOUTD+1),hl                              ;#4104: 22 E5 FE
        ld      (BIOS_HOUTD),a                                 ;#4107: 32 E4 FE
        ld      a,Z80_RST_18                                   ;#410A: 3E DF
        ld      (BREAKPOINT_A_OPCODE),a                        ;#410C: 32 6E EC
        ld      (BREAKPOINT_B_OPCODE),a                        ;#410F: 32 71 EC
MEGA_PROMPT_LOOP:
        ; First entry after init — resets SP, primes MEGA_PROMPT_TICK
        ld      sp,(MEGA_SAVED_SP)                             ;#4112: ED 7B FC F9
        call    PRINT_CR                                       ;#4116: CD B4 42
MEGA_PROMPT_TICK:
        ; Per-line restart of the assembler's read-execute loop
        ld      sp,(MEGA_SAVED_SP)                             ;#4119: ED 7B FC F9
        ld      ix,MEGA_STATE_FLAGS                            ;#411D: DD 21 F5 F9
        bit     3,(ix)                                         ;#4121: DD CB 00 5E
        call    nz,CASSETTE_STOP_READ                          ;#4125: C4 32 43
PROMPT_TICK_AFTER_RESET:
        ; Mid-TICK entry that skips SP reset; clears MEGA_STATE_FLAGS via ld (ix),0
        ld      (ix),0                                         ;#4128: DD 36 00 00
PROMPT_TICK_PRESERVE_FLAGS:
        ; Re-entry that skips both SP reset and the flag-clear; reached from AUTO 4189
        bit     3,(ix)                                         ;#412C: DD CB 00 5E
        jr      nz,PROMPT_TICK_READ_LINE                       ;#4130: 20 10
        bit     7,(ix)                                         ;#4132: DD CB 00 7E
        jr      z,PROMPT_TICK_PROMPT                           ;#4136: 28 05
PROMPT_TICK_HOOK_BIT7:
        ; Bit-7 path of MEGA_STATE_FLAGS at TICK entry — calls AUTO line printer
        call    PROMPT_TICK_AUTO_LINE                          ;#4138: CD 25 4E
        jr      PROMPT_TICK_READ_LINE                          ;#413B: 18 05

PROMPT_TICK_PROMPT:
        ; Print the `>` prompt character via PRINT_CHAR
        ld      a,">"                                          ;#413D: 3E 3E
        call    PRINT_CHAR                                     ;#413F: CD B6 42
PROMPT_TICK_READ_LINE:
        ; Restore SP and call READ_INPUT_LINE (4B92h) with TICK pushed as return
        ld      sp,(MEGA_SAVED_SP)                             ;#4142: ED 7B FC F9
        ld      hl,MEGA_PROMPT_TICK                            ;#4146: 21 19 41
        push    hl                                             ;#4149: E5
        call    READ_INPUT_LINE                                ;#414A: CD 92 4B
        ld      hl,(MEGA_INPUT_LINE_PTR)                       ;#414D: 2A FE F9
        ld      a,(hl)                                         ;#4150: 7E
        cp      ">"                                            ;#4151: FE 3E
        jr      nz,PROMPT_TICK_PARSE                           ;#4153: 20 01
        inc     hl                                             ;#4155: 23
PROMPT_TICK_PARSE:
        ; After optional `>` skipped — parse the first token
        call    SKIP_SPACES                                    ;#4156: CD F3 43
        ret     z                                              ;#4159: C8
        call    PARSE_LINE_NUMBER                              ;#415A: CD 3E 4F
        jr      c,SYNTAX_ERROR                                 ;#415D: 38 5A
        jr      z,PROMPT_TICK_PCMD_LOOKUP                      ;#415F: 28 2B
        ld      de,(MEGA_LINE_NUMBER)                          ;#4161: ED 5B 0D EC
        ld      a,d                                            ;#4165: 7A
        or      e                                              ;#4166: B3
        jp      z,SYNTAX_ERROR                                 ;#4167: CA B9 41
        bit     7,(ix)                                         ;#416A: DD CB 00 7E
        jr      z,PROMPT_TICK_LINE_BODY                        ;#416E: 28 10
        push    hl                                             ;#4170: E5
        ld      hl,(MEGA_AUTO_LINE_NUMBER)                     ;#4171: 2A 14 EC
        call    COMPARE_HL_DE                                  ;#4174: CD 98 50
        pop     hl                                             ;#4177: E1
        ld      a,0FFh                                         ;#4178: 3E FF
        jr      z,PROMPT_TICK_AUTO_SAVEFLAG                    ;#417A: 28 01
        xor     a                                              ;#417C: AF
PROMPT_TICK_AUTO_SAVEFLAG:
        ; Stash AUTO-match flag (FFh if line = AUTO target, else 0)
        ld      (MEGA_AUTO_FIRST_FLAG),a                       ;#417D: 32 13 EC
PROMPT_TICK_LINE_BODY:
        ; Skip optional space, then call FIND_AND_MEASURE_LINE (insert into program)
        ld      a,(hl)                                         ;#4180: 7E
        cp      " "                                            ;#4181: FE 20
        jr      nz,PROMPT_TICK_LINE_INSERT                     ;#4183: 20 01
        inc     hl                                             ;#4185: 23
PROMPT_TICK_LINE_INSERT:
        ; Already past the space — fall straight into FIND_AND_MEASURE_LINE
        call    FIND_AND_MEASURE_LINE                          ;#4186: CD 55 4E
        jp      PROMPT_TICK_PRESERVE_FLAGS                     ;#4189: C3 2C 41

PROMPT_TICK_PCMD_LOOKUP:
        ; Walk MEGA_PCMD_TABLE (6B45) looking for a name match
        ld      de,MEGA_PCMD_TABLE                             ;#418C: 11 45 6B
PCMD_LOOKUP_NEXT:
        ; Per-record entry of PROMPT_TICK_PCMD_LOOKUP — push HL, read next name byte
        push    hl                                             ;#418F: E5
PCMD_LOOKUP_READ_NAME:
        ; Re-entry skipping push HL — read next name byte (end-of-table=0)
        ld      a,(de)                                         ;#4190: 1A
        and     7Fh                                            ;#4191: E6 7F
        jr      z,SYNTAX_ERROR                                 ;#4193: 28 24
        ld      c,a                                            ;#4195: 4F
        ld      a,(hl)                                         ;#4196: 7E
        call    TO_UPPER                                       ;#4197: CD 22 47
        cp      c                                              ;#419A: B9
        jr      z,PCMD_LOOKUP_MATCH                            ;#419B: 28 0A
PCMD_LOOKUP_SKIP_NAME:
        ; Mismatch: walk DE past rest of name (until bit-7), then past 2-byte handler addr
        ld      a,(de)                                         ;#419D: 1A
        inc     de                                             ;#419E: 13
        rla                                                    ;#419F: 17
        jr      nc,PCMD_LOOKUP_SKIP_NAME                       ;#41A0: 30 FB
        inc     de                                             ;#41A2: 13
        inc     de                                             ;#41A3: 13
        pop     hl                                             ;#41A4: E1
        jr      PCMD_LOOKUP_NEXT                               ;#41A5: 18 E8

PCMD_LOOKUP_MATCH:
        ; Name char matched: advance DE/HL; on terminator follow handler addr
        ld      a,(de)                                         ;#41A7: 1A
        inc     de                                             ;#41A8: 13
        inc     hl                                             ;#41A9: 23
        rla                                                    ;#41AA: 17
        jr      nc,PCMD_LOOKUP_READ_NAME                       ;#41AB: 30 E3
        ld      a,(de)                                         ;#41AD: 1A
        inc     de                                             ;#41AE: 13
        ex      (sp),hl                                        ;#41AF: E3
        ld      l,a                                            ;#41B0: 6F
        ld      a,(de)                                         ;#41B1: 1A
        ld      h,a                                            ;#41B2: 67
        ex      (sp),hl                                        ;#41B3: E3
        ret                                                    ;#41B4: C9

PROMPT_TICK_TAIL_CHECK:
        ; Skip trailing whitespace; RET if line consumed, else fall into SYNTAX_ERROR
        call    SKIP_SPACES                                    ;#41B5: CD F3 43
        ret     z                                              ;#41B8: C8
SYNTAX_ERROR:
        ; Print `?\a\r` and jp MEGA_PROMPT_TICK (does not return to caller)
        call    PRINT_INLINE_STRING                            ;#41B9: CD 8A 50
        db      "?", 7, 8Dh                                    ;#41BC: 3F 07 8D
        jp      MEGA_PROMPT_TICK                               ;#41BF: C3 19 41

READ_NEXT_USER_BYTE:
        ; Disasm byte fetch: slot-aware read at MEGA_DISASM_CURSOR, advance, return A/C
        push    hl                                             ;#41C2: E5
        ld      hl,(MEGA_DISASM_CURSOR)                        ;#41C3: 2A 5E EC
        call    MEGA_SLOT_READ_HL                              ;#41C6: CD 16 FA
        inc     hl                                             ;#41C9: 23
        ld      (MEGA_DISASM_CURSOR),hl                        ;#41CA: 22 5E EC
        pop     hl                                             ;#41CD: E1
        ld      c,a                                            ;#41CE: 4F
        ret                                                    ;#41CF: C9

LDIR_BYTE_FROM_DE:
        ; Single-byte fetch helper for slot-aware LDIR: exx; ex de,hl; jp SLOT_READ_HL
        exx                                                    ;#41D0: D9
        ex      de,hl                                          ;#41D1: EB
        jp      MEGA_SLOT_READ_HL                              ;#41D2: C3 16 FA

LDIR_BYTE_TO_HL:
        ; Single-byte store helper for slot-aware LDIR: write E at (HL); inc HL; dec BC
        ld      a,e                                            ;#41D5: 7B
        call    MEGA_SLOT_WRITE                                ;#41D6: CD 10 FA
        inc     hl                                             ;#41D9: 23
        dec     bc                                             ;#41DA: 0B
        ret                                                    ;#41DB: C9
        ld      hl,(MEGA_DIRBUF_SAV)                           ;#41DC: 2A C1 EC
        ld      (BIOS_DIRBUF),hl                               ;#41DF: 22 51 F3
        ld      hl,(MEGA_SAVED_HL)                             ;#41E2: 2A FA F9
        or      a                                              ;#41E5: B7
        ret                                                    ;#41E6: C9

PRINT_OVERFLOW:
        ; Print "Sobrecarga\a\r" and return (overflow error wrapper)
        call    PRINT_INLINE_STRING                            ;#41E7: CD 8A 50
        db      "Sobrecarga", 7, 8Dh                           ;#41EA: 53 6F 62 72 65 63 61 72 67 61 07 8D
        ret                                                    ;#41F6: C9

PRINT_OUT_OF_MEMORY:
        ; Print "Falta memoria \a\r" and return (out-of-memory wrapper)
        call    PRINT_INLINE_STRING                            ;#41F7: CD 8A 50
        db      "Falta memoria ", 7, 8Dh                       ;#41FA: 46 61 6C 74 61 20 6D 65 6D 6F 72 69 61 20 07 8D
        ret                                                    ;#420A: C9

PRINT_PASS_1_BANNER:
        ; Print "PASSO-1\r" — assembler pass 1 banner
        call    PRINT_INLINE_STRING                            ;#420B: CD 8A 50
        db      "PASSO-1", 0Dh, 8Dh                            ;#420E: 50 41 53 53 4F 2D 31 0D 8D
        ret                                                    ;#4217: C9

PRINT_PASS_2_BANNER:
        ; Print "PASSO-2\r" — assembler pass 2 banner
        call    PRINT_INLINE_STRING                            ;#4218: CD 8A 50
        db      "PASSO-2", 0Dh, 8Dh                            ;#421B: 50 41 53 53 4F 2D 32 0D 8D
        ret                                                    ;#4224: C9

PRINT_PASS_2_DONE:
        ; Print "Fim do PASSO-2\r" — pass 2 completed
        call    PRINT_INLINE_STRING                            ;#4225: CD 8A 50
        db      "Fim do PASSO-2", 8Dh                          ;#4228: 46 69 6D 20 64 6F 20 50 41 53 53 4F 2D 32 8D
        ret                                                    ;#4237: C9

PRINT_LABEL_TABLE_FULL:
        ; Print "Fim da tabela de Etiquetas\a\r" — label table exhausted
        call    PRINT_INLINE_STRING                            ;#4238: CD 8A 50
        db      "Fim da tabela de Etiquetas", 7, 8Dh           ;#423B: 46 69 6D 20 64 61 20 74 61 62 65 6C 61 20 64 65 20 45 74 69 71 75 65 74 61 73 07 8D
        ret                                                    ;#4257: C9
        nop                                                    ;#4258: 00
        nop                                                    ;#4259: 00

SLOT_DRIVER_TEMPLATE_SRC:
        ; ROM source of the 48-byte slot-switching driver (LDIRed to FA00h)

        phase   0FA00h
MEGA_HOOK_FA00:
        ; RAM hook slot 0 — slot-switch entry; patched with RET (C=0) or driver (C=1)
        ; 48-byte slot-switching driver, copied to MEGA_HOOK_FA00 (FA00h) by
        ; MEGA_INIT_BODY's LDIR (4055..405Eh) on the C=1 (CALL START) path. The
        ; `[phase]` directive makes labels inside the region resolve to their runtime
        ; addresses (FA00..FA2F), which is where every `call MEGA_SLOT_*` site in
        ; the cart jumps to.
        ; Layout (8/8/6/6/6/7/7 = 48 bytes):
        ; FA00 MEGA_HOOK_FA00     DI; switch primary slot (A8h) to template byte; ret
        ; FA08 MEGA_HOOK_FA08     same body, but EI before returning (used as exit)
        ; FA10 MEGA_SLOT_WRITE    `ld (hl),a` between two slot switches
        ; FA16 MEGA_SLOT_READ_HL  `ld a,(hl)`
        ; FA1C MEGA_SLOT_READ_DE  `ld a,(de)`
        ; FA22 MEGA_SLOT_LDIR     block copy
        ; FA29 MEGA_SLOT_LDDR     reverse block copy
        ; The `ld a,0` immediate at FA02/FA09 is a template byte that the installer
        ; at 693Ch patches with the cart's actual slot byte so the switch-back
        ; targets the correct slot. (The decoded `0` in the asm is the unmodified
        ; template value; at runtime the literal differs per host machine.)
        di                                                     ;#FA00: F3
        push    af                                             ;#FA01: F5
        ld      a,0                                            ;#FA02: 3E 00
        out     (0A8h),a                                       ;#FA04: D3 A8
        pop     af                                             ;#FA06: F1
        ret                                                    ;#FA07: C9

MEGA_HOOK_FA08:
        ; RAM hook slot 1 — restores slot, EI variant
        push    af                                             ;#FA08: F5
        ld      a,0                                            ;#FA09: 3E 00
        out     (0A8h),a                                       ;#FA0B: D3 A8
        pop     af                                             ;#FA0D: F1
MEGA_HOOK_EI_PATCH:
        ; SMC byte inside MEGA_HOOK_FA08 — 0FBh = EI, 0 = disabled (cassette routes patch)
        ei                                                     ;#FA0E: FB
        ret                                                    ;#FA0F: C9

MEGA_SLOT_WRITE:
        ; Slot-switched write helper — `ld (hl),a` in the foreign slot, then restore
        call    MEGA_HOOK_FA00                                 ;#FA10: CD 00 FA
        ld      (hl),a                                         ;#FA13: 77
        jr      MEGA_HOOK_FA08                                 ;#FA14: 18 F2

MEGA_SLOT_READ_HL:
        ; Slot-switched read helper — `ld a,(hl)` in the foreign slot, then restore
        call    MEGA_HOOK_FA00                                 ;#FA16: CD 00 FA
        ld      a,(hl)                                         ;#FA19: 7E
        jr      MEGA_HOOK_FA08                                 ;#FA1A: 18 EC

MEGA_SLOT_READ_DE:
        ; Slot-switched read helper — `ld a,(de)` in the foreign slot, then restore
        call    MEGA_HOOK_FA00                                 ;#FA1C: CD 00 FA
        ld      a,(de)                                         ;#FA1F: 1A
        jr      MEGA_HOOK_FA08                                 ;#FA20: 18 E6

MEGA_SLOT_LDIR:
        ; Slot-switched block copy (LDIR) helper
        call    MEGA_HOOK_FA00                                 ;#FA22: CD 00 FA
        ldir                                                   ;#FA25: ED B0
        jr      MEGA_HOOK_FA08                                 ;#FA27: 18 DF

MEGA_SLOT_LDDR:
        ; Slot-switched reverse block copy (LDDR) helper
        call    MEGA_HOOK_FA00                                 ;#FA29: CD 00 FA
        lddr                                                   ;#FA2C: ED B8
        jr      MEGA_HOOK_FA08                                 ;#FA2E: 18 D8
        dephase

INPUT_LINE_FROM_KBD:
        ; Bit-3-clear path: save IX/IY, call BIOS_PINLIN; on Ctrl-Break jp PROMPT_TICK
        push    ix                                             ;#428A: DD E5
        push    iy                                             ;#428C: FD E5
        call    BIOS_PINLIN                                    ;#428E: CD AE 00
        pop     iy                                             ;#4291: FD E1
        pop     ix                                             ;#4293: DD E1
        jp      c,MEGA_PROMPT_TICK                             ;#4295: DA 19 41
        inc     hl                                             ;#4298: 23
        ld      (MEGA_INPUT_LINE_PTR),hl                       ;#4299: 22 FE F9
        ret                                                    ;#429C: C9

CHECK_USER_INTERRUPT:
        ; Poll CTRL-STOP via BIOS_BREAKX; allow Space to pause, Ctrl-D (04h) to abort
        call    BIOS_BREAKX                                    ;#429D: CD B7 00
        ret     c                                              ;#42A0: D8
        call    BIOS_CHSNS                                     ;#42A1: CD 9C 00
        scf                                                    ;#42A4: 37
        ccf                                                    ;#42A5: 3F
        ret     z                                              ;#42A6: C8
        call    BIOS_CHGET                                     ;#42A7: CD 9F 00
        cp      " "                                            ;#42AA: FE 20
        call    z,BIOS_CHGET                                   ;#42AC: CC 9F 00
        xor     4                                              ;#42AF: EE 04
        ret     nz                                             ;#42B1: C0
        scf                                                    ;#42B2: 37
        ret                                                    ;#42B3: C9

PRINT_CR:
        ; Load A=0Dh and fall into PRINT_CHAR (prints CR+LF to screen)
        ld      a,"\r"                                         ;#42B4: 3E 0D
PRINT_CHAR:
        ; Print A via BIOS_CHPUT (screen) and CR→CR+LF expansion
        call    BIOS_CHPUT                                     ;#42B6: CD A2 00
        cp      0Dh                                            ;#42B9: FE 0D
        ret     nz                                             ;#42BB: C0
        ld      a,"\n"                                         ;#42BC: 3E 0A
        call    BIOS_CHPUT                                     ;#42BE: CD A2 00
        ld      a,"\r"                                         ;#42C1: 3E 0D
        ret                                                    ;#42C3: C9

PRINT_CHAR_DUAL:
        ; Print A to screen plus (if MEGA_STATE_FLAGS bit 1 set) to BIOS_LPTOUT
        call    PRINT_CHAR                                     ;#42C4: CD B6 42
        bit     1,(ix)                                         ;#42C7: DD CB 00 4E
        ret     z                                              ;#42CB: C8
LPT_OUT_WITH_LF:
        ; BIOS_LPTOUT wrapper: emit A; if A was CR (0Dh), recurse with 0Ah for CRLF
        call    BIOS_LPTOUT                                    ;#42CC: CD A5 00
        jp      c,SYNTAX_ERROR                                 ;#42CF: DA B9 41
        cp      0Dh                                            ;#42D2: FE 0D
        ret     nz                                             ;#42D4: C0
        ld      a,"\n"                                         ;#42D5: 3E 0A
        call    LPT_OUT_WITH_LF                                ;#42D7: CD CC 42
        ld      a,"\r"                                         ;#42DA: 3E 0D
        ret                                                    ;#42DC: C9

CASSETTE_TAPOON_AF:
        ; A=0AFh + register-preserving BIOS_TAPOON call (cassette long-header mode)
        OVERLAP_LD_A                                           ;#42DD: 3E
BIOS_TAPOON_PRESERVE:
        ; Register-preserving BIOS_TAPOON wrapper (entry that skips the ld a,0AFh)
        xor     a                                              ;#42DE: AF
        push    hl                                             ;#42DF: E5
        push    de                                             ;#42E0: D5
        push    bc                                             ;#42E1: C5
        push    ix                                             ;#42E2: DD E5
        push    iy                                             ;#42E4: FD E5
        call    BIOS_TAPOON                                    ;#42E6: CD EA 00
        pop     iy                                             ;#42E9: FD E1
        pop     ix                                             ;#42EB: DD E1
        pop     bc                                             ;#42ED: C1
        pop     de                                             ;#42EE: D1
        pop     hl                                             ;#42EF: E1
        ret     nc                                             ;#42F0: D0
CASSETTE_ABORT:
        ; Tape-error tail used by CASSETTE_PUT_BYTE — cleanup + jp SYNTAX_ERROR
        call    CASSETTE_STOP_WRITE                            ;#42F1: CD 3E 43
        res     3,(ix)                                         ;#42F4: DD CB 00 9E
        jp      SYNTAX_ERROR                                   ;#42F8: C3 B9 41

CASSETTE_PUT_BYTE:
        ; Save all regs, call BIOS_TAPOUT, restore; on error fall into CASSETTE_ABORT
        push    af                                             ;#42FB: F5
        push    hl                                             ;#42FC: E5
        push    de                                             ;#42FD: D5
        push    bc                                             ;#42FE: C5
        push    ix                                             ;#42FF: DD E5
        push    iy                                             ;#4301: FD E5
        call    BIOS_TAPOUT                                    ;#4303: CD ED 00
        pop     iy                                             ;#4306: FD E1
        pop     ix                                             ;#4308: DD E1
        pop     bc                                             ;#430A: C1
        pop     de                                             ;#430B: D1
        pop     hl                                             ;#430C: E1
        jr      c,CASSETTE_ABORT                               ;#430D: 38 E2
        pop     af                                             ;#430F: F1
        ret                                                    ;#4310: C9

CASSETTE_START_READ:
        ; Save all regs, call BIOS_TAPION, restore — paired with CASSETTE_PUT_BYTE
        push    hl                                             ;#4311: E5
        push    de                                             ;#4312: D5
        push    bc                                             ;#4313: C5
        push    ix                                             ;#4314: DD E5
        push    iy                                             ;#4316: FD E5
        call    BIOS_TAPION                                    ;#4318: CD E1 00
CASSETTE_RESTORE_AND_CHECK:
        ; Pop-5-regs tail of START_READ/GET_BYTE; raise SYNTAX_ERROR on tape CF=1
        pop     iy                                             ;#431B: FD E1
        pop     ix                                             ;#431D: DD E1
        pop     bc                                             ;#431F: C1
        pop     de                                             ;#4320: D1
        pop     hl                                             ;#4321: E1
        ret     nc                                             ;#4322: D0
CASSETTE_RESTORE_RAISE:
        ; jp SYNTAX_ERROR — tape error fall-through after register restore
        jp      SYNTAX_ERROR                                   ;#4323: C3 B9 41

CASSETTE_GET_BYTE:
        ; Save all regs, call BIOS_TAPIN, share pop-all tail at 431B — reads tape byte
        push    hl                                             ;#4326: E5
        push    de                                             ;#4327: D5
        push    bc                                             ;#4328: C5
        push    ix                                             ;#4329: DD E5
        push    iy                                             ;#432B: FD E5
        call    BIOS_TAPIN                                     ;#432D: CD E4 00
        jr      CASSETTE_RESTORE_AND_CHECK                     ;#4330: 18 E9

CASSETTE_STOP_READ:
        ; Save IX/IY, call BIOS_TAPIOF (tape input off), restore — paired with TAPION
        push    ix                                             ;#4332: DD E5
        push    iy                                             ;#4334: FD E5
        call    BIOS_TAPIOF                                    ;#4336: CD E7 00
CASSETTE_STOP_TAIL:
        ; Shared pop iy/ix/ret tail for both _STOP_READ and _STOP_WRITE
        pop     iy                                             ;#4339: FD E1
        pop     ix                                             ;#433B: DD E1
        ret                                                    ;#433D: C9

CASSETTE_STOP_WRITE:
        ; Save IX/IY, call BIOS_TAPOOF (tape output off), restore — paired with TAPOON
        push    ix                                             ;#433E: DD E5
        push    iy                                             ;#4340: FD E5
        call    BIOS_TAPOOF                                    ;#4342: CD F0 00
        jr      CASSETTE_STOP_TAIL                             ;#4345: 18 F2

SYNTAX_ERROR_LF:
        ; Print "?" + BEL + CR via CHPUT, then jp MEGA_PROMPT_TICK
        call    PRINT_QMARK_BEL                                ;#4347: CD 50 43
        call    PRINT_CR                                       ;#434A: CD B4 42
MEGA_RESUME_PROMPT:
        ; `jp MEGA_PROMPT_TICK` — silent return-to-prompt (no `?\a\r` print)
        jp      MEGA_PROMPT_TICK                               ;#434D: C3 19 41

PRINT_QMARK_BEL:
        ; Print "?" + raw BEL byte through BIOS_CHPUT
        ld      a,"?"                                          ;#4350: 3E 3F
        call    PRINT_CHAR                                     ;#4352: CD B6 42
        ld      a,7                                            ;#4355: 3E 07
        jp      BIOS_CHPUT                                     ;#4357: C3 A2 00

MEGA_PCMD_INTEL:
        ; Prompt command "INTEL" — set state bit 6 (Intel-hex format) then fall into R
        set     6,(ix)                                         ;#435A: DD CB 00 F6
MEGA_PCMD_R:
        ; Prompt command "R" — read bytes (own format or Intel-hex if state bit 6 set)
        call    SKIP_SPACES                                    ;#435E: CD F3 43
        ld      de,0                                           ;#4361: 11 00 00
        call    nz,PARSE_HEX_WORD_AND_EOL                      ;#4364: C4 E1 43
        ld      (MEGA_ASM_RELOC_OFFSET),de                     ;#4367: ED 53 F8 F9
        ld      sp,0FAF5h                                      ;#436B: 31 F5 FA
        set     3,(ix)                                         ;#436E: DD CB 00 DE
        call    CASSETTE_START_READ                            ;#4372: CD 11 43
R_TAPE_WAIT_COLON:
        ; Skip tape bytes until the ':' line-start marker is seen; fall into hex parser
        call    CASSETTE_GET_BYTE                              ;#4375: CD 26 43
        sub     ":"                                            ;#4378: D6 3A
        jr      nz,R_TAPE_WAIT_COLON                           ;#437A: 20 F9
        ld      e,a                                            ;#437C: 5F
        call    READ_TAPE_HEX_BYTE                             ;#437D: CD D0 43
        or      a                                              ;#4380: B7
        jr      z,R_TAPE_EOF                                   ;#4381: 28 2F
        ld      b,a                                            ;#4383: 47
        call    READ_TAPE_HEX_BYTE                             ;#4384: CD D0 43
        ld      h,a                                            ;#4387: 67
        call    READ_TAPE_HEX_BYTE                             ;#4388: CD D0 43
        ld      l,a                                            ;#438B: 6F
        push    de                                             ;#438C: D5
        ld      de,(MEGA_ASM_RELOC_OFFSET)                     ;#438D: ED 5B F8 F9
        add     hl,de                                          ;#4391: 19
        pop     de                                             ;#4392: D1
        call    READ_TAPE_HEX_BYTE                             ;#4393: CD D0 43
R_TAPE_HEX_BYTE_LOOP:
        ; Per-byte body — read hex byte from tape, store at HL, advance
        call    READ_TAPE_HEX_BYTE                             ;#4396: CD D0 43
        ld      (hl),a                                         ;#4399: 77
        nop                                                    ;#439A: 00
        nop                                                    ;#439B: 00
        inc     hl                                             ;#439C: 23
        djnz    R_TAPE_HEX_BYTE_LOOP                           ;#439D: 10 F7
        call    READ_TAPE_HEX_BYTE                             ;#439F: CD D0 43
        jr      nz,R_TAPE_ERROR                                ;#43A2: 20 22
        bit     6,(ix)                                         ;#43A4: DD CB 00 76
        jr      nz,R_TAPE_WAIT_COLON                           ;#43A8: 20 CB
        call    CASSETTE_STOP_READ                             ;#43AA: CD 32 43
        call    CASSETTE_START_READ                            ;#43AD: CD 11 43
        jr      R_TAPE_WAIT_COLON                              ;#43B0: 18 C3

R_TAPE_EOF:
        ; Length byte = 0 → end-of-file: TAPE_DELAY_2, stop read, clear bit 3, return
        call    TAPE_DELAY_2                                   ;#43B2: CD 80 4B
        call    CASSETTE_STOP_READ                             ;#43B5: CD 32 43
        res     3,(ix)                                         ;#43B8: DD CB 00 9E
        jp      MEGA_RESUME_PROMPT                             ;#43BC: C3 4D 43

READ_TAPE_HEX_CHAR:
        ; Read one byte from tape, parse as hex digit; on invalid → abort with error
        call    CASSETTE_GET_BYTE                              ;#43BF: CD 26 43
        call    PARSE_HEX_CHAR                                 ;#43C2: CD E7 50
        ret     nc                                             ;#43C5: D0
R_TAPE_ERROR:
        ; Bad hex byte / checksum: stop tape, clear bit 3, jp SYNTAX_ERROR_LF
        call    CASSETTE_STOP_READ                             ;#43C6: CD 32 43
        res     3,(ix)                                         ;#43C9: DD CB 00 9E
        jp      SYNTAX_ERROR_LF                                ;#43CD: C3 47 43

READ_TAPE_HEX_BYTE:
        ; Read 2 hex digits from tape, combine to byte, add into running E checksum
        call    READ_TAPE_HEX_CHAR                             ;#43D0: CD BF 43
        add     a,a                                            ;#43D3: 87
        add     a,a                                            ;#43D4: 87
        add     a,a                                            ;#43D5: 87
        add     a,a                                            ;#43D6: 87
        ld      d,a                                            ;#43D7: 57
        call    READ_TAPE_HEX_CHAR                             ;#43D8: CD BF 43
        or      d                                              ;#43DB: B2
        ld      d,a                                            ;#43DC: 57
        add     a,e                                            ;#43DD: 83
        ld      e,a                                            ;#43DE: 5F
        ld      a,d                                            ;#43DF: 7A
        ret                                                    ;#43E0: C9

PARSE_HEX_WORD_AND_EOL:
        ; Parse hex word into DE then require end-of-line (Z), else raise error
        call    PARSE_HEX_WORD                                 ;#43E1: CD BA 50
        jr      c,PARSE_HEX_WORD_AND_EOL_ERR                   ;#43E4: 38 04
        call    SKIP_SPACES                                    ;#43E6: CD F3 43
        ret     z                                              ;#43E9: C8
PARSE_HEX_WORD_AND_EOL_ERR:
        ; Parse-fail / non-EOL tail: jp SYNTAX_ERROR_LF
        jp      SYNTAX_ERROR_LF                                ;#43EA: C3 47 43

PRINT_SPACE:
        ; Print a single space character (A=20h; jp PRINT_CHAR)
        ld      a," "                                          ;#43ED: 3E 20
        jp      PRINT_CHAR                                     ;#43EF: C3 B6 42

SKIP_SPACES_ADVANCE:
        ; Advance HL then fall into SKIP_SPACES — used as a loop back-edge
        inc     hl                                             ;#43F2: 23
SKIP_SPACES:
        ; Walk HL past spaces; returns Z if A=0 at terminator
        ld      a,(hl)                                         ;#43F3: 7E
        cp      " "                                            ;#43F4: FE 20
        jr      z,SKIP_SPACES_ADVANCE                          ;#43F6: 28 FA
        or      a                                              ;#43F8: B7
        ret                                                    ;#43F9: C9

INIT_ASSEMBLER_STATE:
        ; Zero EC27..EC3F (asm scratch), seed stack top, save I reg, init PROCNM ptr
        ld      hl,MEGA_ASM_STATE_AREA                         ;#43FA: 21 27 EC
        ld      b,19h                                          ;#43FD: 06 19
        xor     a                                              ;#43FF: AF
INIT_ASM_STATE_ZERO_LOOP:
        ; Per-byte body — zero 19h-byte ASM scratch at EC27h
        ld      (hl),a                                         ;#4400: 77
        inc     hl                                             ;#4401: 23
        djnz    INIT_ASM_STATE_ZERO_LOOP                       ;#4402: 10 FC
        dec     a                                              ;#4404: 3D
        ld      (MEGA_ASM_STACK_TOP),a                         ;#4405: 32 40 EC
        ld      a,i                                            ;#4408: ED 57
        ld      (MEGA_I_REG_SAVE),a                            ;#440A: 32 2F EC
        ld      hl,BIOS_PROCNM                                 ;#440D: 21 89 FD
        ld      (MEGA_PROCNM_PTR),hl                           ;#4410: 22 29 EC
        ret                                                    ;#4413: C9

PRINT_NUL_STRING_INDIRECT:
        ; Print 0-terminated string via inline 2-byte LE pointer after the call
        ex      (sp),hl                                        ;#4414: E3
        push    de                                             ;#4415: D5
        call    LOAD_LE_WORD_INC                               ;#4416: CD 26 44
PRINT_NUL_STRING_LOOP:
        ; Loop body: ld a,(de); ret if 0, else print, inc, loop
        ld      a,(de)                                         ;#4419: 1A
        or      a                                              ;#441A: B7
        jr      z,PRINT_NUL_STRING_DONE                        ;#441B: 28 06
        call    PRINT_CHAR                                     ;#441D: CD B6 42
        inc     de                                             ;#4420: 13
        jr      PRINT_NUL_STRING_LOOP                          ;#4421: 18 F6

PRINT_NUL_STRING_DONE:
        ; Tail of PRINT_NUL_STRING_LOOP — restore DE/HL and return on the 0 byte
        pop     de                                             ;#4423: D1
        ex      (sp),hl                                        ;#4424: E3
        ret                                                    ;#4425: C9

LOAD_LE_WORD_INC:
        ; Read 2-byte LE word from (HL) into DE; advance HL by 2
        ld      e,(hl)                                         ;#4426: 5E
        inc     hl                                             ;#4427: 23
        ld      d,(hl)                                         ;#4428: 56
        inc     hl                                             ;#4429: 23
        ret                                                    ;#442A: C9

MEGA_PCMD_X:
        ; Prompt command "X" — eXamine: print saved register snapshot or set "X reg=val"
        ld      a,(hl)                                         ;#442B: 7E
        or      a                                              ;#442C: B7
        jp      nz,MEGA_PCMD_X_SET                             ;#442D: C2 F1 44
MEGA_PCMD_X_SHOW:
        ; Dump saved register snapshot (no-arg path)
        call    PRINT_NUL_STRING_INDIRECT                      ;#4430: CD 14 44
        sbc     a,d                                            ;#4433: 9A
        ld      b,h                                            ;#4434: 44
        ld      b,8                                            ;#4435: 06 08
        ld      hl,MEGA_USER_REGS_TAIL                         ;#4437: 21 3F EC
MEGA_PCMD_X_DUMP_BYTE:
        ; Per-byte body — print 8 saved single-reg bytes as hex
        call    PRINT_SPACE                                    ;#443A: CD ED 43
        ld      a,(hl)                                         ;#443D: 7E
        dec     hl                                             ;#443E: 2B
        call    PRINT_HEX_A                                    ;#443F: CD A3 50
        djnz    MEGA_PCMD_X_DUMP_BYTE                          ;#4442: 10 F6
        call    PRINT_FLAGS_AS_LETTERS                         ;#4444: CD 76 44
        call    PRINT_CR                                       ;#4447: CD B4 42
        call    PRINT_NUL_STRING_INDIRECT                      ;#444A: CD 14 44
        or      h                                              ;#444D: B4
        ld      b,h                                            ;#444E: 44
        ld      b,9                                            ;#444F: 06 09
MEGA_PCMD_X_DUMP_WORD:
        ; Per-byte body — print 9 saved word-reg bytes as hex
        call    PRINT_SPACE                                    ;#4451: CD ED 43
        ld      a,(hl)                                         ;#4454: 7E
        dec     hl                                             ;#4455: 2B
        call    PRINT_HEX_A                                    ;#4456: CD A3 50
        djnz    MEGA_PCMD_X_DUMP_WORD                          ;#4459: 10 F6
        call    PRINT_CR                                       ;#445B: CD B4 42
        call    PRINT_NUL_STRING_INDIRECT                      ;#445E: CD 14 44
        ret     nc                                             ;#4461: D0
        ld      b,h                                            ;#4462: 44
        ld      b,4                                            ;#4463: 06 04
MEGA_PCMD_X_DUMP_PAIR:
        ; Per-pair body — print 4 saved register pairs as hex words
        call    PRINT_SPACE                                    ;#4465: CD ED 43
        ld      d,(hl)                                         ;#4468: 56
        dec     hl                                             ;#4469: 2B
        ld      e,(hl)                                         ;#446A: 5E
        dec     hl                                             ;#446B: 2B
        ex      de,hl                                          ;#446C: EB
        call    PRINT_HEX_HL                                   ;#446D: CD 9E 50
        ex      de,hl                                          ;#4470: EB
        djnz    MEGA_PCMD_X_DUMP_PAIR                          ;#4471: 10 F2
        jp      PRINT_CR                                       ;#4473: C3 B4 42

PRINT_FLAGS_AS_LETTERS:
        ; Print flag-register letters from (EC3E): bit 7→'S', 6→'Z', 2→'V', 0→'C'
        call    PRINT_SPACE                                    ;#4476: CD ED 43
        ld      a,(MEGA_USER_FLAGS_SAVE)                       ;#4479: 3A 3E EC
        ld      c,a                                            ;#447C: 4F
        bit     7,c                                            ;#447D: CB 79
        ld      a,"S"                                          ;#447F: 3E 53
        call    nz,PRINT_CHAR                                  ;#4481: C4 B6 42
        bit     6,c                                            ;#4484: CB 71
        ld      a,"Z"                                          ;#4486: 3E 5A
        call    nz,PRINT_CHAR                                  ;#4488: C4 B6 42
        bit     2,c                                            ;#448B: CB 51
        ld      a,"V"                                          ;#448D: 3E 56
        call    nz,PRINT_CHAR                                  ;#448F: C4 B6 42
        bit     0,c                                            ;#4492: CB 41
        ld      a,"C"                                          ;#4494: 3E 43
        call    nz,PRINT_CHAR                                  ;#4496: C4 B6 42
        ret                                                    ;#4499: C9
        db      0Dh, " A  F  B  C  D  E  H  L", 0Dh            ;#449A: 0D 20 41 20 20 46 20 20 42 20 20 43 20 20 44 20 20 45 20 20 48 20 20 4C 0D
        db      0                                              ;#44B3: 00
        db      " A' F' B' C' D' E' H' L' I", 0Dh              ;#44B4: 20 41 27 20 46 27 20 42 27 20 43 27 20 44 27 20 45 27 20 48 27 20 4C 27 20 49 0D
        db      0                                              ;#44CF: 00
        db      " IX   IY   SP   PC", 0Dh                      ;#44D0: 20 49 58 20 20 20 49 59 20 20 20 53 50 20 20 20 50 43 0D
        db      0                                              ;#44E3: 00

REGISTER_LETTER_TABLE:
        ; 13-byte cpir lookup "AFBCDEHL\rXYS\r" — maps reg-name letter to slot
        ; Format: FORMAT_RAW_STRING
        ; - For embedded text that isn't 0-terminated or bit-7-terminated.
        db      "AFBCDEHL", 0Dh, "XYS", 0Dh                    ;#44E4: 41 46 42 43 44 45 48 4C 0D 58 59 53 0D

MEGA_PCMD_X_SET:
        ; `X reg=val` arm — read register letter, look it up in REGISTER_LETTER_TABLE
        ld      b,a                                            ;#44F1: 47
        inc     hl                                             ;#44F2: 23
        call    SKIP_SPACES                                    ;#44F3: CD F3 43
        jr      nz,X_REG_LOOKUP_FAIL                           ;#44F6: 20 09
        ld      a,b                                            ;#44F8: 78
        ld      hl,REGISTER_LETTER_TABLE                       ;#44F9: 21 E4 44
        ld      bc,0Dh                                         ;#44FC: 01 0D 00
        cpir                                                   ;#44FF: ED B1
X_REG_LOOKUP_FAIL:
        ; CPIR for the named register missed — jp SYNTAX_ERROR_LF
        jp      nz,SYNTAX_ERROR_LF                             ;#4501: C2 47 43
        ld      a,c                                            ;#4504: 79
        cp      5                                              ;#4505: FE 05
        jr      c,X_REG_DISPATCH                               ;#4507: 38 03
        add     a,8                                            ;#4509: C6 08
        ld      c,a                                            ;#450B: 4F
X_REG_DISPATCH:
        ; Per-reg setup: load B/C, compute HL = pointer into X's reg-name table
        ld      b,0                                            ;#450C: 06 00
        ld      h,b                                            ;#450E: 60
        ld      l,c                                            ;#450F: 69
        ld      a,c                                            ;#4510: 79
        cp      4                                              ;#4511: FE 04
        ld      de,X_REG_NAME_BASE_HIGH                        ;#4513: 11 D8 44
        jr      nc,X_REG_INDEX_BC                              ;#4516: 30 04
        ld      de,X_REG_NAME_BASE_LOW                         ;#4518: 11 E0 44
        add     hl,hl                                          ;#451B: 29
X_REG_INDEX_BC:
        ; Compute HL = name-table offset (C*4 + B) for the chosen register
        add     hl,hl                                          ;#451C: 29
        add     hl,bc                                          ;#451D: 09
        ex      de,hl                                          ;#451E: EB
        or      a                                              ;#451F: B7
        sbc     hl,de                                          ;#4520: ED 52
        call    SKIP_SPACES                                    ;#4522: CD F3 43
X_PRINT_REG_NAME_LOOP:
        ; Print bytes from (HL) via PRINT_CHAR until a non-printable byte (<'!')
        ld      a,(hl)                                         ;#4525: 7E
        cp      "!"                                            ;#4526: FE 21
        jr      c,X_REG_PRINT_PAD                              ;#4528: 38 07
        call    PRINT_CHAR                                     ;#452A: CD B6 42
        inc     hl                                             ;#452D: 23
        inc     b                                              ;#452E: 04
        jr      X_PRINT_REG_NAME_LOOP                          ;#452F: 18 F4

X_REG_PRINT_PAD:
        ; After name: pad with 3-B spaces, fall into the value-print / edit dispatch
        ld      a,3                                            ;#4531: 3E 03
        sub     b                                              ;#4533: 90
        ld      b,a                                            ;#4534: 47
X_REG_PRINT_PAD_LOOP:
        ; Per-space body — pad register name out to 3 columns
        call    PRINT_SPACE                                    ;#4535: CD ED 43
        djnz    X_REG_PRINT_PAD_LOOP                           ;#4538: 10 FB
        ld      a,c                                            ;#453A: 79
        cp      4                                              ;#453B: FE 04
        jr      c,X_EDIT_RP                                    ;#453D: 38 30
        ld      hl,MEGA_USER_REGS_SAVE                         ;#453F: 21 2B EC
        add     hl,bc                                          ;#4542: 09
        ld      a,(hl)                                         ;#4543: 7E
        ld      b,a                                            ;#4544: 47
        call    PRINT_HEX_A                                    ;#4545: CD A3 50
        call    PRINT_SPACE                                    ;#4548: CD ED 43
        call    READ_KEY_AS_HEX                                ;#454B: CD 14 47
        call    nc,READ_KEY_HEX_BYTE_RAW                       ;#454E: D4 37 47
        jr      c,X_REG_INPUT_CR_CHECK                         ;#4551: 38 05
        call    MEGA_PCMD_X_PREV_REG                           ;#4553: CD CC 45
        jr      X_STORE_BYTE_PRINT_CR                          ;#4556: 18 0C

X_REG_INPUT_CR_CHECK:
        ; Raw-hex path: not a hex digit — test for CR (commit) vs nav key
        cp      "\r"                                           ;#4558: FE 0D
        jr      nz,X_REG_INPUT_NAV                             ;#455A: 20 03
        ld      (hl),b                                         ;#455C: 70
        jr      X_PRINT_CR_TAIL                                ;#455D: 18 53

X_REG_INPUT_NAV:
        ; Not CR — try MEGA_PCMD_X_NAV_KEY (`\` prev / `^` next)
        call    MEGA_PCMD_X_NAV_KEY                            ;#455F: CD B5 45
        jr      c,X_BAD_KEY                                    ;#4562: 38 06
X_STORE_BYTE_PRINT_CR:
        ; Store edited byte into reg slot, fall into PRINT_CR
        ld      (hl),b                                         ;#4564: 70
X_PRINT_CR_NEXT:
        ; Print CR and jr to X_NEXT_REG (shared tail)
        call    PRINT_CR                                       ;#4565: CD B4 42
X_NEXT_REG:
        ; Loop tail: re-enter the X-command per-register prompt at 450C
        jr      X_REG_DISPATCH                                 ;#4568: 18 A2

X_BAD_KEY:
        ; Invalid edit key: PRINT_QMARK_BEL then jr to common "print CR, next reg" tail
        call    PRINT_QMARK_BEL                                ;#456A: CD 50 43
        jr      X_PRINT_CR_NEXT                                ;#456D: 18 F6

X_EDIT_RP:
        ; 16-bit register edit: load RP value, prompt for 4 hex digits, store back
        ld      hl,MEGA_ASM_STATE_AREA                         ;#456F: 21 27 EC
        add     hl,bc                                          ;#4572: 09
        add     hl,bc                                          ;#4573: 09
        push    hl                                             ;#4574: E5
        call    LOAD_LE_WORD_INC                               ;#4575: CD 26 44
        ex      de,hl                                          ;#4578: EB
        call    PRINT_HEX_HL                                   ;#4579: CD 9E 50
        call    PRINT_SPACE                                    ;#457C: CD ED 43
        ld      hl,0                                           ;#457F: 21 00 00
        ld      d,h                                            ;#4582: 54
        ld      e,l                                            ;#4583: 5D
        ld      b,4                                            ;#4584: 06 04
X_REG_INPUT_RP_DIGIT:
        ; Per-nibble body — accumulate 4 hex digits into HL for RP edit
        call    READ_KEY_AS_HEX                                ;#4586: CD 14 47
        jr      c,X_REG_INPUT_RP_NONHEX                        ;#4589: 38 0F
        ld      e,a                                            ;#458B: 5F
        add     hl,hl                                          ;#458C: 29
        add     hl,hl                                          ;#458D: 29
        add     hl,hl                                          ;#458E: 29
        add     hl,hl                                          ;#458F: 29
        add     hl,de                                          ;#4590: 19
        djnz    X_REG_INPUT_RP_DIGIT                           ;#4591: 10 F3
        ex      de,hl                                          ;#4593: EB
        pop     hl                                             ;#4594: E1
        call    MEGA_PCMD_X_PREV_REG                           ;#4595: CD CC 45
        jr      X_REG_INPUT_RP_NAV_TAIL                        ;#4598: 18 0B

X_REG_INPUT_RP_NONHEX:
        ; 16-bit-edit path: non-hex key — pop saved HL, test for CR/nav
        ex      de,hl                                          ;#459A: EB
        pop     hl                                             ;#459B: E1
        cp      0Dh                                            ;#459C: FE 0D
        jr      z,X_STORE_AND_PRINT_CR                         ;#459E: 28 0A
        call    MEGA_PCMD_X_NAV_KEY                            ;#45A0: CD B5 45
        jr      c,X_BAD_KEY                                    ;#45A3: 38 C5
X_REG_INPUT_RP_NAV_TAIL:
        ; RP-edit nav-key path: store word + CR + next reg
        call    X_STORE_AND_PRINT_CR                           ;#45A5: CD AA 45
        jr      X_NEXT_REG                                     ;#45A8: 18 BE

X_STORE_AND_PRINT_CR:
        ; Store DE at (hl)/(hl+1) (unless reg-slot 4 = SP-special), then jp PRINT_CR
        ld      a,b                                            ;#45AA: 78
        cp      4                                              ;#45AB: FE 04
        jr      z,X_PRINT_CR_TAIL                              ;#45AD: 28 03
        ld      (hl),e                                         ;#45AF: 73
        inc     hl                                             ;#45B0: 23
        ld      (hl),d                                         ;#45B1: 72
X_PRINT_CR_TAIL:
        ; Skip-store path (slot 4 = SP): just jp PRINT_CR for the trailing newline
        jp      PRINT_CR                                       ;#45B2: C3 B4 42

MEGA_PCMD_X_NAV_KEY:
        ; Handle X-command navigation keys: `\` (5Ch) = prev reg, `^` (5Eh) = next reg
        cp      5Ch                                            ;#45B5: FE 5C
        jr      z,MEGA_PCMD_X_PREV_REG                         ;#45B7: 28 13
        cp      5Eh                                            ;#45B9: FE 5E
        scf                                                    ;#45BB: 37
        ret     nz                                             ;#45BC: C0
        inc     c                                              ;#45BD: 0C
        ld      a,4                                            ;#45BE: 3E 04
        cp      c                                              ;#45C0: B9
        jr      nz,X_NAV_NEXT_CHECK_END                        ;#45C1: 20 01
        inc     c                                              ;#45C3: 0C
X_NAV_NEXT_CHECK_END:
        ; `^` next path: skip slot 4 if reached, check upper-bound 14h (wrap to 1)
        ld      a,14h                                          ;#45C4: 3E 14
        cp      c                                              ;#45C6: B9
        ret     nc                                             ;#45C7: D0
        ld      c,1                                            ;#45C8: 0E 01
        or      a                                              ;#45CA: B7
        ret                                                    ;#45CB: C9

MEGA_PCMD_X_PREV_REG:
        ; Cursor-back through X's register list: wrap to 14h, skip slot 4, dec c
        dec     c                                              ;#45CC: 0D
        jp      z,X_NAV_PREV_WRAP                              ;#45CD: CA D7 45
        ld      a,4                                            ;#45D0: 3E 04
        cp      c                                              ;#45D2: B9
        jr      nz,X_NAV_PREV_DONE                             ;#45D3: 20 04
        dec     c                                              ;#45D5: 0D
        ret                                                    ;#45D6: C9

X_NAV_PREV_WRAP:
        ; `\` prev path: slot 0 → wrap to 14h
        ld      c,14h                                          ;#45D7: 0E 14
X_NAV_PREV_DONE:
        ; Common return: clear CF and ret
        or      a                                              ;#45D9: B7
        ret                                                    ;#45DA: C9

X_SAVE_USER_CONTEXT:
        ; Save full user CPU state (AF/BC/DE/HL × 2 + IX/IY + SP) into MEGA_USER_REGS_SAVE
        ld      (MEGA_SAVED_SP_X),sp                           ;#45DB: ED 73 41 EC
        di                                                     ;#45DF: F3
        ld      sp,MEGA_ASM_STACK_TOP                          ;#45E0: 31 40 EC
        push    af                                             ;#45E3: F5
        push    bc                                             ;#45E4: C5
        push    de                                             ;#45E5: D5
        push    hl                                             ;#45E6: E5
        ex      af,af'                                         ;#45E7: 08
        exx                                                    ;#45E8: D9
        push    af                                             ;#45E9: F5
        push    bc                                             ;#45EA: C5
        push    de                                             ;#45EB: D5
        push    hl                                             ;#45EC: E5
        dec     sp                                             ;#45ED: 3B
        push    ix                                             ;#45EE: DD E5
        push    iy                                             ;#45F0: FD E5
X_SAVE_RESTORE_DEBUG_SP:
        ; Reload debugger SP from MEGA_SAVED_SP_X and EI/RET tail
        ld      sp,(MEGA_SAVED_SP_X)                           ;#45F2: ED 7B 41 EC
        ei                                                     ;#45F6: FB
        ret                                                    ;#45F7: C9

X_RESTORE_USER_CONTEXT:
        ; Restore full user CPU state from MEGA_USER_REGS_SAVE — paired with X_SAVE
        ld      (MEGA_SAVED_SP_X),sp                           ;#45F8: ED 73 41 EC
        di                                                     ;#45FC: F3
        ld      sp,MEGA_USER_REGS_SAVE                         ;#45FD: 31 2B EC
        pop     iy                                             ;#4600: FD E1
        pop     ix                                             ;#4602: DD E1
        inc     sp                                             ;#4604: 33
        pop     hl                                             ;#4605: E1
        pop     de                                             ;#4606: D1
        pop     bc                                             ;#4607: C1
        pop     af                                             ;#4608: F1
        ex      af,af'                                         ;#4609: 08
        exx                                                    ;#460A: D9
        pop     hl                                             ;#460B: E1
        pop     de                                             ;#460C: D1
        pop     bc                                             ;#460D: C1
        pop     af                                             ;#460E: F1
        jr      X_SAVE_RESTORE_DEBUG_SP                        ;#460F: 18 E1

MEGA_PCMD_G:
        ; Prompt command "G addr[,bp1[,bp2]]" — Go with up to 2 breakpoints
        call    SKIP_SPACES                                    ;#4611: CD F3 43
        scf                                                    ;#4614: 37
        call    nz,PARSE_HEX_WORD                              ;#4615: C4 BA 50
        jr      c,MEGA_PCMD_G_SYNTAX_ERR                       ;#4618: 38 52
        ld      a,(hl)                                         ;#461A: 7E
        or      a                                              ;#461B: B7
        jr      z,MEGA_PCMD_G_LAUNCH_USER                      ;#461C: 28 3C
        cp      ","                                            ;#461E: FE 2C
        jr      nz,MEGA_PCMD_G_SYNTAX_ERR                      ;#4620: 20 4A
        push    de                                             ;#4622: D5
        inc     hl                                             ;#4623: 23
        call    PARSE_HEX_WORD                                 ;#4624: CD BA 50
        jr      c,MEGA_PCMD_G_SYNTAX_ERR                       ;#4627: 38 43
        ld      a,(hl)                                         ;#4629: 7E
        or      a                                              ;#462A: B7
        jr      z,MEGA_PCMD_G_INSTALL_BP_A                     ;#462B: 28 22
        cp      ","                                            ;#462D: FE 2C
        jr      nz,MEGA_PCMD_G_SYNTAX_ERR                      ;#462F: 20 3B
        push    de                                             ;#4631: D5
        inc     hl                                             ;#4632: 23
        call    PARSE_HEX_WORD                                 ;#4633: CD BA 50
        jr      c,MEGA_PCMD_G_SYNTAX_ERR                       ;#4636: 38 34
        call    SKIP_SPACES                                    ;#4638: CD F3 43
        jr      nz,MEGA_PCMD_G_SYNTAX_ERR                      ;#463B: 20 2F
        ex      de,hl                                          ;#463D: EB
        pop     de                                             ;#463E: D1
        push    hl                                             ;#463F: E5
        or      a                                              ;#4640: B7
        sbc     hl,de                                          ;#4641: ED 52
        pop     hl                                             ;#4643: E1
        jr      z,MEGA_PCMD_G_INSTALL_BP_A                     ;#4644: 28 09
MEGA_PCMD_G_INSTALL_BP_B:
        ; Install RST8h at bp2's address, save the original byte to BREAKPOINT_B_OPCODE
        ld      (MEGA_BP_B_ADDR),hl                            ;#4646: 22 72 EC
        ld      a,(hl)                                         ;#4649: 7E
        ld      (BREAKPOINT_B_OPCODE),a                        ;#464A: 32 71 EC
        ld      (hl),Z80_RST_18                                ;#464D: 36 DF
MEGA_PCMD_G_INSTALL_BP_A:
        ; Install RST8h at bp1's address (reached whenever ≥1 breakpoint was parsed)
        ex      de,hl                                          ;#464F: EB
        ld      (MEGA_BP_A_ADDR),hl                            ;#4650: 22 6F EC
        ld      a,(hl)                                         ;#4653: 7E
        ld      (BREAKPOINT_A_OPCODE),a                        ;#4654: 32 6E EC
        ld      (hl),Z80_RST_18                                ;#4657: 36 DF
        pop     de                                             ;#4659: D1
MEGA_PCMD_G_LAUNCH_USER:
        ; Stash run address in MEGA_ASM_STATE_AREA, restore user CPU state, jp via stack
        ld      (MEGA_ASM_STATE_AREA),de                       ;#465A: ED 53 27 EC
        call    X_RESTORE_USER_CONTEXT                         ;#465E: CD F8 45
        ei                                                     ;#4661: FB
        ld      sp,(MEGA_PROCNM_PTR)                           ;#4662: ED 7B 29 EC
        push    hl                                             ;#4666: E5
        ld      hl,(MEGA_ASM_STATE_AREA)                       ;#4667: 2A 27 EC
        ex      (sp),hl                                        ;#466A: E3
        ret                                                    ;#466B: C9

MEGA_PCMD_G_SYNTAX_ERR:
        ; jr-reachable trampoline jumping to SYNTAX_ERROR_LF (reached from 6 PARSE checks)
        jp      SYNTAX_ERROR_LF                                ;#466C: C3 47 43

HOUTD_HOOK:
        ; Hook installed at BIOS HOUTD (FEE4); checks breakpoints before passthrough
        ; HOUTD_HOOK — breakpoint interceptor. MEGA installs
        ; `JP HOUTD_HOOK` at BIOS_HOUTD (FEE4h) during boot. When user code
        ; executes a `RST 18h` (opcode DFh), the BIOS routes through HOUTD,
        ; which jumps here. The hook then peeks the return address (= the
        ; BP target+1, since RST pushed return-after-RST), and compares it
        ; against MEGA_BP_A_ADDR / MEGA_BP_B_ADDR. If neither matches OR
        ; if the corresponding BREAKPOINT_*_OPCODE has been disarmed to
        ; DFh, the hook restores its register state and passes through to
        ; the chain-saved BIOS_HOUTD_PASSTHROUGH. On match it tears down
        ; the user stack, restores the cart's prompt SP, saves the user
        ; register snapshot via X_SAVE_USER_CONTEXT (so the X-command can
        ; inspect it), reverts the patched bytes at both BPs, and disarms
        ; both BREAKPOINT_*_OPCODE markers (breakpoints are one-shot —
        ; after firing once they need to be re-armed via G).
        push    af                                             ;#466F: F5
        push    de                                             ;#4670: D5
        push    hl                                             ;#4671: E5
        ld      hl,0Ah                                         ;#4672: 21 0A 00
        add     hl,sp                                          ;#4675: 39
        ld      e,(hl)                                         ;#4676: 5E
        inc     hl                                             ;#4677: 23
        ld      d,(hl)                                         ;#4678: 56
        dec     de                                             ;#4679: 1B
        ld      a,(BREAKPOINT_A_OPCODE)                        ;#467A: 3A 6E EC
        cp      Z80_RST_18                                     ;#467D: FE DF
        jr      z,HOUTD_HOOK_PASSTHROUGH                       ;#467F: 28 17
        ld      hl,(MEGA_BP_A_ADDR)                            ;#4681: 2A 6F EC
        or      a                                              ;#4684: B7
        sbc     hl,de                                          ;#4685: ED 52
        jr      z,HOUTD_HOOK_BP_HIT                            ;#4687: 28 15
        ld      a,(BREAKPOINT_B_OPCODE)                        ;#4689: 3A 71 EC
        cp      Z80_RST_18                                     ;#468C: FE DF
        jr      z,HOUTD_HOOK_PASSTHROUGH                       ;#468E: 28 08
        ld      hl,(MEGA_BP_B_ADDR)                            ;#4690: 2A 72 EC
        or      a                                              ;#4693: B7
        sbc     hl,de                                          ;#4694: ED 52
        jr      z,HOUTD_HOOK_BP_HIT                            ;#4696: 28 06
HOUTD_HOOK_PASSTHROUGH:
        ; No BP match: restore regs (af/de/hl) and jp BIOS_HOUTD_PASSTHROUGH
        pop     hl                                             ;#4698: E1
        pop     de                                             ;#4699: D1
        pop     af                                             ;#469A: F1
        jp      BIOS_HOUTD_PASSTHROUGH                         ;#469B: C3 74 EC

HOUTD_HOOK_BP_HIT:
        ; BP matched: save user state, restore original opcodes, return to MEGA prompt
        ld      a,i                                            ;#469E: ED 57
        di                                                     ;#46A0: F3
        ld      (MEGA_I_REG_SAVE),a                            ;#46A1: 32 2F EC
        ld      a,80h                                          ;#46A4: 3E 80
        jp      pe,HOUTD_HOOK_SAVE_PV                          ;#46A6: EA AA 46
        xor     a                                              ;#46A9: AF
HOUTD_HOOK_SAVE_PV:
        ; Common arm: save bit-7 (parity = IFF2) into MEGA_ASM_STACK_TOP for X restore
        ld      (MEGA_ASM_STACK_TOP),a                         ;#46AA: 32 40 EC
        pop     hl                                             ;#46AD: E1
        pop     de                                             ;#46AE: D1
        pop     af                                             ;#46AF: F1
        pop     af                                             ;#46B0: F1
        pop     af                                             ;#46B1: F1
        ex      (sp),hl                                        ;#46B2: E3
        dec     hl                                             ;#46B3: 2B
        ld      (MEGA_ASM_STATE_AREA),hl                       ;#46B4: 22 27 EC
        pop     hl                                             ;#46B7: E1
        ld      (MEGA_PROCNM_PTR),sp                           ;#46B8: ED 73 29 EC
        ld      sp,(MEGA_SAVED_SP)                             ;#46BC: ED 7B FC F9
        call    X_SAVE_USER_CONTEXT                            ;#46C0: CD DB 45
        ld      a,(BREAKPOINT_A_OPCODE)                        ;#46C3: 3A 6E EC
        cp      Z80_RST_18                                     ;#46C6: FE DF
        jr      z,HOUTD_HOOK_DISARM_BPS                        ;#46C8: 28 0F
        ld      hl,(MEGA_BP_A_ADDR)                            ;#46CA: 2A 6F EC
        ld      (hl),a                                         ;#46CD: 77
        ld      a,(BREAKPOINT_B_OPCODE)                        ;#46CE: 3A 71 EC
        cp      Z80_RST_18                                     ;#46D1: FE DF
        jr      z,HOUTD_HOOK_DISARM_BPS                        ;#46D3: 28 04
        ld      hl,(MEGA_BP_B_ADDR)                            ;#46D5: 2A 72 EC
        ld      (hl),a                                         ;#46D8: 77
HOUTD_HOOK_DISARM_BPS:
        ; Write DFh (RST 18 = "no BP") into both BREAKPOINT_*_OPCODE — disarms both BPs
        ld      a,0DFh                                         ;#46D9: 3E DF
        ld      (BREAKPOINT_A_OPCODE),a                        ;#46DB: 32 6E EC
        ld      (BREAKPOINT_B_OPCODE),a                        ;#46DE: 32 71 EC
        ld      a,(BIOS_SCRMOD)                                ;#46E1: 3A AF FC
        cp      2                                              ;#46E4: FE 02
        call    nc,BIOS_INIT32                                 ;#46E6: D4 6F 00
        call    MEGA_PCMD_X_SHOW                               ;#46E9: CD 30 44
        jp      MEGA_RESUME_PROMPT                             ;#46EC: C3 4D 43

READ_KEY_HEX_OR_REMAP:
        ; If (ix) bit 5 set, CHGET via HEX_INPUT_KEY_TABLE remap; else fall into 4714
        bit     5,(ix)                                         ;#46EF: DD CB 00 6E
        jr      z,READ_KEY_AS_HEX                              ;#46F3: 28 1F
        call    BIOS_CHGET                                     ;#46F5: CD 9F 00
        call    TO_UPPER                                       ;#46F8: CD 22 47
        push    hl                                             ;#46FB: E5
        push    bc                                             ;#46FC: C5
        ld      hl,HEX_INPUT_KEY_TABLE                         ;#46FD: 21 45 47
        ld      bc,10h                                         ;#4700: 01 10 00
        cpir                                                   ;#4703: ED B1
        jr      nz,REMAP_KEY_RESTORE                           ;#4705: 20 09
        ld      a,c                                            ;#4707: 79
        cp      0Ah                                            ;#4708: FE 0A
        jr      c,REMAP_KEY_ADD_BIAS                           ;#470A: 38 02
        add     a,7                                            ;#470C: C6 07
REMAP_KEY_ADD_BIAS:
        ; CPIR hit on row >=A: bias up via `add a,7`; both arms then add "0"
        add     a,"0"                                          ;#470E: C6 30
REMAP_KEY_RESTORE:
        ; CPIR-miss path: pop saved BC/HL and jr to common return (4712 → 471A)
        pop     bc                                             ;#4710: C1
        pop     hl                                             ;#4711: E1
        jr      READ_KEY_AS_HEX_ECHO                           ;#4712: 18 06

READ_KEY_AS_HEX:
        ; CHGET + uppercase + echo (if printable) + PARSE_HEX_CHAR — keyboard hex read
        call    BIOS_CHGET                                     ;#4714: CD 9F 00
        call    TO_UPPER                                       ;#4717: CD 22 47
READ_KEY_AS_HEX_ECHO:
        ; Echo printable A via PRINT_CHAR, fall into PARSE_HEX
        cp      " "                                            ;#471A: FE 20
        call    nc,PRINT_CHAR                                  ;#471C: D4 B6 42
        jp      PARSE_HEX_CHAR                                 ;#471F: C3 E7 50

TO_UPPER:
        ; Convert A to uppercase: maps 'a'..'z' → 'A'..'Z'; other A unchanged
        cp      "a"                                            ;#4722: FE 61
        ret     c                                              ;#4724: D8
        cp      "z"+1                                          ;#4725: FE 7B
        ret     nc                                             ;#4727: D0
        sub     " "                                            ;#4728: D6 20
        ret                                                    ;#472A: C9

READ_KEY_HEX_BYTE:
        ; Read 2 hex digits from keyboard into B (uses fast-remap if bit 5 of state set)
        bit     5,(ix)                                         ;#472B: DD CB 00 6E
        jr      z,READ_KEY_HEX_BYTE_RAW                        ;#472F: 28 06
        ld      b,a                                            ;#4731: 47
        call    READ_KEY_HEX_OR_REMAP                          ;#4732: CD EF 46
        jr      READ_KEY_HEX_BYTE_TAIL                         ;#4735: 18 04

READ_KEY_HEX_BYTE_RAW:
        ; Bypass fast-remap: save A→B, read second nibble via READ_KEY_AS_HEX, combine
        ld      b,a                                            ;#4737: 47
        call    READ_KEY_AS_HEX                                ;#4738: CD 14 47
READ_KEY_HEX_BYTE_TAIL:
        ; Combine high B + low A into B; ret c on CR/abort
        ret     c                                              ;#473B: D8
        ld      e,a                                            ;#473C: 5F
        ld      a,b                                            ;#473D: 78
        add     a,a                                            ;#473E: 87
        add     a,a                                            ;#473F: 87
        add     a,a                                            ;#4740: 87
        add     a,a                                            ;#4741: 87
        or      e                                              ;#4742: B3
        ld      b,a                                            ;#4743: 47
        ret                                                    ;#4744: C9

HEX_INPUT_KEY_TABLE:
        ; 16-byte key→hex remap searched by cpir; position N maps to hex (15-N)
        ; HEX_INPUT_KEY_TABLE — 4x4 calculator-style hex-digit overlay on
        ; the MSX QWERTY keyboard. Position N (0..15) holds the ASCII of the
        ; key that maps to hex digit (15-N). The 16 keys form a 4x4 grid
        ; arranged so the user can type hex without moving their hand off the
        ; keyboard's right side:
        ;
        ; keyboard:    mapped to:
        ; 7 8 9 0      7 8 9 A
        ; U I O P      4 5 6 B
        ; J K L Ç      1 2 3 C
        ; M , . /      0 F E D
        ;
        ; Row 1 (the QWERTY digit row) handles digits 7-A on the left half;
        ; rows 2-4 give the lower digits + B-F via UIOP/JKLÇ/M,./ on the
        ; right-hand side. READ_KEY_HEX_OR_REMAP cpir-searches the table when
        ; bit 5 of (ix) is set, returning hex value (15 - position).
        ; Format: FORMAT_RAW_STRING
        ; - For embedded text that isn't 0-terminated or bit-7-terminated.
        db      ",./", 80h, "P0987OIULKJM"                     ;#4745: 2C 2E 2F 80 50 30 39 38 37 4F 49 55 4C 4B 4A 4D

MEGA_PCMD_S:
        ; Prompt command "S" — set state bit 5 then fall into M (Set range mode)
        set     5,(ix)                                         ;#4755: DD CB 00 EE
MEGA_PCMD_M:
        ; Prompt command "M addr" — interactive Modify memory (prompts new byte per addr)
        call    SKIP_SPACES                                    ;#4759: CD F3 43
        ld      de,(MEGA_LAST_MEM_ADDR)                        ;#475C: ED 5B 43 EC
        call    nz,PARSE_HEX_WORD_AND_EOL                      ;#4760: C4 E1 43
        ex      de,hl                                          ;#4763: EB
MEM_EDIT_NEW_ROW:
        ; Print addr + first space, fall into per-byte prompt at MEM_EDIT_NEXT_BYTE
        call    PRINT_HEX_HL                                   ;#4764: CD 9E 50
MEM_EDIT_NEXT_BYTE:
        ; Print space + current byte + "-" then read 2 hex digits for the replacement
        call    PRINT_SPACE                                    ;#4767: CD ED 43
        ld      a,(hl)                                         ;#476A: 7E
        call    PRINT_HEX_A                                    ;#476B: CD A3 50
        ld      a,"-"                                          ;#476E: 3E 2D
        call    PRINT_CHAR                                     ;#4770: CD B6 42
        call    READ_KEY_HEX_OR_REMAP                          ;#4773: CD EF 46
        jr      c,MEM_EDIT_KEY_DISPATCH                        ;#4776: 38 11
        call    READ_KEY_HEX_BYTE                              ;#4778: CD 2B 47
        jr      c,MEM_EDIT_CR_GUARD                            ;#477B: 38 18
        ld      (hl),b                                         ;#477D: 70
MEM_EDIT_ADVANCE:
        ; Advance HL after stored byte; CR every 4 bytes
        inc     hl                                             ;#477E: 23
        ld      a,l                                            ;#477F: 7D
        and     3                                              ;#4780: E6 03
        jr      nz,MEM_EDIT_NEXT_BYTE                          ;#4782: 20 E3
MEM_EDIT_END_ROW:
        ; After 4 bytes written, emit CR and jr 4764h to start the next memory row
        call    PRINT_CR                                       ;#4784: CD B4 42
        jr      MEM_EDIT_NEW_ROW                               ;#4787: 18 DB

MEM_EDIT_KEY_DISPATCH:
        ; Non-hex first-key dispatch: SPACE = skip / BS = back / CR = exit
        cp      " "                                            ;#4789: FE 20
        jr      z,MEM_EDIT_SKIP_BYTE                           ;#478B: 28 0F
        cp      CHAR_BS                                        ;#478D: FE 08
        jr      z,MEM_EDIT_BACK                                ;#478F: 28 10
        cp      "\r"                                           ;#4791: FE 0D
        jr      z,MEM_EDIT_EXIT                                ;#4793: 28 14
MEM_EDIT_CR_GUARD:
        ; CR after a partial 1-digit input: commit if CR, else jr to ?-bell error
        cp      "\r"                                           ;#4795: FE 0D
        jr      nz,MEM_EDIT_BAD_KEY                            ;#4797: 20 0B
        ld      (hl),b                                         ;#4799: 70
        jr      MEM_EDIT_EXIT                                  ;#479A: 18 0D

MEM_EDIT_SKIP_BYTE:
        ; SPACE arm: print one space and advance to next byte (skip without edit)
        call    PRINT_SPACE                                    ;#479C: CD ED 43
        jr      MEM_EDIT_ADVANCE                               ;#479F: 18 DD

MEM_EDIT_BACK:
        ; BS arm: dec HL one byte and re-prompt the row (back-step in M)
        dec     hl                                             ;#47A1: 2B
        jr      MEM_EDIT_END_ROW                               ;#47A2: 18 E0

MEM_EDIT_BAD_KEY:
        ; Bad key arm: PRINT_QMARK_BEL then jr to MEM_EDIT_END_ROW to re-prompt
        call    PRINT_QMARK_BEL                                ;#47A4: CD 50 43
        jr      MEM_EDIT_END_ROW                               ;#47A7: 18 DB

MEM_EDIT_EXIT:
        ; Save current HL into MEGA_LAST_MEM_ADDR, PRINT_CR, ret — exits the M command
        ld      (MEGA_LAST_MEM_ADDR),hl                        ;#47A9: 22 43 EC
        call    PRINT_CR                                       ;#47AC: CD B4 42
        ret                                                    ;#47AF: C9

MEGA_PCMD_C:
        ; Prompt command "C n" — set display bytes-per-line mode at MEGA_PCMD_C_MODE
        ld      b,(hl)                                         ;#47B0: 46
        inc     hl                                             ;#47B1: 23
        call    SKIP_SPACES                                    ;#47B2: CD F3 43
        jp      nz,SYNTAX_ERROR_LF                             ;#47B5: C2 47 43
        ld      a,b                                            ;#47B8: 78
        sub     "0"                                            ;#47B9: D6 30
        jp      c,SYNTAX_ERROR_LF                              ;#47BB: DA 47 43
        cp      4                                              ;#47BE: FE 04
        jp      nc,SYNTAX_ERROR_LF                             ;#47C0: D2 47 43
        ld      (MEGA_PCMD_C_MODE),a                           ;#47C3: 32 6D EC
        ret                                                    ;#47C6: C9

MEGA_PCMD_V:
        ; Prompt command "V" — set state bit 5 (verify mode) then fall into P → D
        set     5,(ix)                                         ;#47C7: DD CB 00 EE
        jr      MEGA_PCMD_P                                    ;#47CB: 18 00

MEGA_PCMD_P:
        ; Prompt command "P" — set state bit 1 (printer echo) then fall into D
        set     1,(ix)                                         ;#47CD: DD CB 00 CE
MEGA_PCMD_D:
        ; Prompt command "D start[,end]" — display/disassemble memory range
        call    SKIP_SPACES                                    ;#47D1: CD F3 43
        call    PARSE_HEX_WORD                                 ;#47D4: CD BA 50
MEGA_PCMD_D_ERR:
        ; D-command syntax error: jp c, SYNTAX_ERROR_LF — 3 jr callers converge here
        jp      c,SYNTAX_ERROR_LF                              ;#47D7: DA 47 43
        ld      a,(hl)                                         ;#47DA: 7E
        or      a                                              ;#47DB: B7
        jr      z,MEGA_PCMD_D_NO_END                           ;#47DC: 28 13
        cp      ","                                            ;#47DE: FE 2C
        scf                                                    ;#47E0: 37
        jr      nz,MEGA_PCMD_D_ERR                             ;#47E1: 20 F4
        push    de                                             ;#47E3: D5
        inc     hl                                             ;#47E4: 23
        call    PARSE_HEX_WORD_AND_EOL                         ;#47E5: CD E1 43
        pop     hl                                             ;#47E8: E1
        ex      de,hl                                          ;#47E9: EB
        call    COMPARE_HL_DE                                  ;#47EA: CD 98 50
        jr      c,MEGA_PCMD_D_ERR                              ;#47ED: 38 E8
        jr      MEGA_PCMD_D_LOOP                               ;#47EF: 18 09

MEGA_PCMD_D_NO_END:
        ; No end-address given: end ← start+0Fh (or FFFFh if it overflows)
        ld      hl,0Fh                                         ;#47F1: 21 0F 00
        add     hl,de                                          ;#47F4: 19
        jr      nc,MEGA_PCMD_D_LOOP                            ;#47F5: 30 03
        ld      hl,0FFFFh                                      ;#47F7: 21 FF FF
MEGA_PCMD_D_LOOP:
        ; D-command display loop: range/disasm-mode check, interrupt check, emit one line
        bit     5,(ix)                                         ;#47FA: DD CB 00 6E
        jr      z,MEGA_PCMD_D_ROW_ENTRY                        ;#47FE: 28 05
        ld      a,"?"                                          ;#4800: 3E 3F
        cp      h                                              ;#4802: BC
        jr      c,MEGA_PCMD_D_ERR                              ;#4803: 38 D2
MEGA_PCMD_D_ROW_ENTRY:
        ; Common entry from bit-5-clear path — exx then fall into ROW_LOOP
        exx                                                    ;#4805: D9
MEGA_PCMD_D_ROW_LOOP:
        ; Per-row body: CHECK_USER_INTERRUPT, clear line, format hex-addr/bytes/text
        call    CHECK_USER_INTERRUPT                           ;#4806: CD 9D 42
        jp      c,MEGA_PCMD_D_RET                              ;#4809: DA 84 48
        call    CLEAR_OUTPUT_LINE_HL                           ;#480C: CD 45 57
        ld      hl,MEGA_DISASM_LINE                            ;#480F: 21 C3 EC
        exx                                                    ;#4812: D9
        ld      a,d                                            ;#4813: 7A
        exx                                                    ;#4814: D9
        call    STORE_HEX_A_AT_HL                              ;#4815: CD 41 56
        exx                                                    ;#4818: D9
        ld      a,e                                            ;#4819: 7B
        exx                                                    ;#481A: D9
        call    STORE_HEX_A_AT_HL                              ;#481B: CD 41 56
        call    D_COMPUTE_COLUMN_LAYOUT                        ;#481E: CD 85 48
MEGA_PCMD_D_TEXT_LOOP:
        ; Per-byte body — copy disasm bytes into MEGA_DISASM_LINE via LDIR
        call    LDIR_BYTE_FROM_DE                              ;#4821: CD D0 41
        bit     5,(ix)                                         ;#4824: DD CB 00 6E
        call    nz,BIOS_RDVRM                                  ;#4828: C4 4A 00
        ex      de,hl                                          ;#482B: EB
        push    af                                             ;#482C: F5
        add     a,c                                            ;#482D: 81
        ld      c,a                                            ;#482E: 4F
        pop     af                                             ;#482F: F1
        exx                                                    ;#4830: D9
        ld      c,a                                            ;#4831: 4F
        cp      " "                                            ;#4832: FE 20
        jr      c,MEGA_PCMD_D_TEXT_DOT                         ;#4834: 38 0C
        cp      "z"+1                                          ;#4836: FE 7B
        jr      c,MEGA_PCMD_D_TEXT_PUT                         ;#4838: 38 0A
        cp      0A0h                                           ;#483A: FE A0
        jr      c,MEGA_PCMD_D_TEXT_DOT                         ;#483C: 38 04
        cp      0E0h                                           ;#483E: FE E0
        jr      c,MEGA_PCMD_D_TEXT_PUT                         ;#4840: 38 02
MEGA_PCMD_D_TEXT_DOT:
        ; Non-printable byte in text column: substitute "." then fall through to put char
        ld      a,"."                                          ;#4842: 3E 2E
MEGA_PCMD_D_TEXT_PUT:
        ; Store char (printable or dot) at (de), advance, append hex form to disasm line
        ld      (de),a                                         ;#4844: 12
        inc     de                                             ;#4845: 13
        ld      a,c                                            ;#4846: 79
        inc     hl                                             ;#4847: 23
        call    STORE_HEX_A_AT_HL                              ;#4848: CD 41 56
        exx                                                    ;#484B: D9
        inc     de                                             ;#484C: 13
        ld      a,d                                            ;#484D: 7A
        or      e                                              ;#484E: B3
        scf                                                    ;#484F: 37
        call    nz,COMPARE_HL_DE                               ;#4850: C4 98 50
        exx                                                    ;#4853: D9
        jr      c,MEGA_PCMD_D_EMIT_ROW                         ;#4854: 38 02
        djnz    MEGA_PCMD_D_TEXT_LOOP                          ;#4856: 10 C9
MEGA_PCMD_D_EMIT_ROW:
        ; End of row: emit checksum, append CR, print via PRINT_CHAR or LPT_OUT_WITH_LF
        push    af                                             ;#4858: F5
        call    D_EMIT_CHECKSUM_LINE                           ;#4859: CD AA 48
        ld      a,"\r"                                         ;#485C: 3E 0D
        ld      (de),a                                         ;#485E: 12
        ld      hl,MEGA_DISASM_LINE                            ;#485F: 21 C3 EC
MEGA_PCMD_D_PRINT_LOOP:
        ; Per-byte print loop: read byte, dispatch on bit 5/1 of (ix), loop until CR
        ld      a,(hl)                                         ;#4862: 7E
        inc     hl                                             ;#4863: 23
        bit     5,(ix)                                         ;#4864: DD CB 00 6E
        jr      z,MEGA_PCMD_D_PRINT_PLAIN                      ;#4868: 28 0E
        bit     1,(ix)                                         ;#486A: DD CB 00 4E
        push    af                                             ;#486E: F5
        call    z,PRINT_CHAR                                   ;#486F: CC B6 42
        pop     af                                             ;#4872: F1
        call    nz,LPT_OUT_WITH_LF                             ;#4873: C4 CC 42
        jr      MEGA_PCMD_D_PRINT_TAIL                         ;#4876: 18 03

MEGA_PCMD_D_PRINT_PLAIN:
        ; Bit-5-clear arm: simple PRINT_CHAR_DUAL (default disasm output)
        call    PRINT_CHAR_DUAL                                ;#4878: CD C4 42
MEGA_PCMD_D_PRINT_TAIL:
        ; Shared post-emit CR test for D print loop
        cp      0Dh                                            ;#487B: FE 0D
        jr      nz,MEGA_PCMD_D_PRINT_LOOP                      ;#487D: 20 E3
        pop     af                                             ;#487F: F1
        jp      nc,MEGA_PCMD_D_ROW_LOOP                        ;#4880: D2 06 48
        or      a                                              ;#4883: B7
MEGA_PCMD_D_RET:
        ; D-command exit (user interrupt or range exhausted) — bare `ret`
        ret                                                    ;#4884: C9

D_COMPUTE_COLUMN_LAYOUT:
        ; Return DE/B (column buffer ptr, byte count) per MEGA_PCMD_C_MODE
        exx                                                    ;#4885: D9
        ld      c,0                                            ;#4886: 0E 00
        ld      a,(MEGA_PCMD_C_MODE)                           ;#4888: 3A 6D EC
        cp      2                                              ;#488B: FE 02
        jr      nz,D_COL_MAIN_ENTRY                            ;#488D: 20 03
        ld      a,d                                            ;#488F: 7A
        add     a,e                                            ;#4890: 83
        ld      c,a                                            ;#4891: 4F
D_COL_MAIN_ENTRY:
        ; Common entry after the bit-5-on subsum capture — proceed with normal layout
        exx                                                    ;#4892: D9
        ld      de,MEGA_DISASM_HEX_END_C0                      ;#4893: 11 D5 EC
        ld      b,4                                            ;#4896: 06 04
        ld      a,(MEGA_PCMD_C_MODE)                           ;#4898: 3A 6D EC
        or      a                                              ;#489B: B7
        ret     z                                              ;#489C: C8
        ld      de,MEGA_DISASM_HEX_END_C1                      ;#489D: 11 F9 EC
        ld      b,10h                                          ;#48A0: 06 10
        dec     a                                              ;#48A2: 3D
        ret     z                                              ;#48A3: C8
        ld      de,MEGA_DISASM_HEX_END_C2                      ;#48A4: 11 E5 EC
        ld      b,8                                            ;#48A7: 06 08
        ret                                                    ;#48A9: C9

D_EMIT_CHECKSUM_LINE:
        ; If MEGA_PCMD_C_MODE>=2, append ":"+hex-sum+CR to MEGA_LIST_MNEM_COL
        ld      a,(MEGA_PCMD_C_MODE)                           ;#48AA: 3A 6D EC
        cp      2                                              ;#48AD: FE 02
        ret     c                                              ;#48AF: D8
        ld      hl,MEGA_LIST_MNEM_COL                          ;#48B0: 21 E1 EC
        ld      (hl),":"                                       ;#48B3: 36 3A
        inc     hl                                             ;#48B5: 23
        exx                                                    ;#48B6: D9
        ld      a,c                                            ;#48B7: 79
        exx                                                    ;#48B8: D9
        call    STORE_HEX_A_AT_HL                              ;#48B9: CD 41 56
        ld      (hl),"\r"                                      ;#48BC: 36 0D
        ret                                                    ;#48BE: C9

MEGA_PCMD_F:
        ; Prompt command "F start,end,byte" — Fill memory range with a byte
        call    PARSE_3_ARGS                                   ;#48BF: CD D4 48
        inc     d                                              ;#48C2: 14
        dec     d                                              ;#48C3: 15
        jp      nz,SYNTAX_ERROR_LF                             ;#48C4: C2 47 43
        inc     hl                                             ;#48C7: 23
        push    hl                                             ;#48C8: E5
        push    bc                                             ;#48C9: C5
        pop     hl                                             ;#48CA: E1
        pop     bc                                             ;#48CB: C1
MEGA_PCMD_F_LOOP:
        ; Per-byte fill loop: LDIR_BYTE_TO_HL, decrement BC, loop until exhausted
        call    LDIR_BYTE_TO_HL                                ;#48CC: CD D5 41
        ld      a,b                                            ;#48CF: 78
        or      c                                              ;#48D0: B1
        jr      nz,MEGA_PCMD_F_LOOP                            ;#48D1: 20 F9
        ret                                                    ;#48D3: C9

PARSE_3_ARGS:
        ; Parse three comma-separated hex words from input; HL/DE/BC ← arg1/3/end
        call    SKIP_SPACES                                    ;#48D4: CD F3 43
        call    PARSE_HEX_WORD                                 ;#48D7: CD BA 50
PARSE_3_ARGS_ERR:
        ; jr-reachable trampoline jp-ing to SYNTAX_ERROR_LF when any of the 3 parses fail
        jp      c,SYNTAX_ERROR_LF                              ;#48DA: DA 47 43
        push    de                                             ;#48DD: D5
        ld      a,(hl)                                         ;#48DE: 7E
        cp      ","                                            ;#48DF: FE 2C
        scf                                                    ;#48E1: 37
        jr      nz,PARSE_3_ARGS_ERR                            ;#48E2: 20 F6
        inc     hl                                             ;#48E4: 23
        call    PARSE_HEX_WORD                                 ;#48E5: CD BA 50
        jr      c,PARSE_3_ARGS_ERR                             ;#48E8: 38 F0
        push    de                                             ;#48EA: D5
        ld      a,(hl)                                         ;#48EB: 7E
        cp      ","                                            ;#48EC: FE 2C
        scf                                                    ;#48EE: 37
        jr      nz,PARSE_3_ARGS_ERR                            ;#48EF: 20 E9
        inc     hl                                             ;#48F1: 23
        call    PARSE_HEX_WORD_AND_EOL                         ;#48F2: CD E1 43
        pop     hl                                             ;#48F5: E1
        pop     bc                                             ;#48F6: C1
        sbc     hl,bc                                          ;#48F7: ED 42
        jr      c,PARSE_3_ARGS_ERR                             ;#48F9: 38 DF
        ret                                                    ;#48FB: C9

MEGA_PCMD_T:
        ; Prompt command "T src,end,dest" — Transfer (move) a memory range
        call    PARSE_3_ARGS                                   ;#48FC: CD D4 48
        push    hl                                             ;#48FF: E5
        ld      h,b                                            ;#4900: 60
        ld      l,c                                            ;#4901: 69
        push    hl                                             ;#4902: E5
        or      a                                              ;#4903: B7
        sbc     hl,de                                          ;#4904: ED 52
        pop     hl                                             ;#4906: E1
        pop     bc                                             ;#4907: C1
        jr      c,MEGA_PCMD_T_LDDR_BWD                         ;#4908: 38 05
        ret     z                                              ;#490A: C8
        inc     bc                                             ;#490B: 03
        jp      MEGA_SLOT_LDIR                                 ;#490C: C3 22 FA

MEGA_PCMD_T_LDDR_BWD:
        ; dst > src in overlapping range: use MEGA_SLOT_LDDR (reverse direction)
        add     hl,bc                                          ;#490F: 09
        ex      de,hl                                          ;#4910: EB
        add     hl,bc                                          ;#4911: 09
        ex      de,hl                                          ;#4912: EB
        inc     bc                                             ;#4913: 03
        jp      MEGA_SLOT_LDDR                                 ;#4914: C3 29 FA

MEGA_PCMD_BA:
        ; Prompt command "BA" — return to BASIC
        ld      sp,(MEGA_SAVED_SP)                             ;#4917: ED 7B FC F9
        ld      hl,BIOS_HOUTD_PASSTHROUGH                      ;#491B: 21 74 EC
        ld      de,BIOS_HOUTD                                  ;#491E: 11 E4 FE
        ld      bc,5                                           ;#4921: 01 05 00
        ldir                                                   ;#4924: ED B0
        jp      MEGA_RETURN_TO_BASIC                           ;#4926: C3 D9 7F
        nop                                                    ;#4929: 00
        nop                                                    ;#492A: 00

MEGA_PCMD_MAP:
        ; Prompt command "MAP" — memory/slot map (uses "Pagina" / " Slot")
        ld      hl,(MEGA_SRC_BUF_START)                        ;#492B: 2A 01 EC
        call    PRINT_HEX_HL                                   ;#492E: CD 9E 50
        ld      a,"-"                                          ;#4931: 3E 2D
        call    PRINT_CHAR                                     ;#4933: CD B6 42
        ld      hl,(MEGA_SRC_BUF_HEAD)                         ;#4936: 2A 03 EC
        inc     hl                                             ;#4939: 23
        call    PRINT_HEX_HL                                   ;#493A: CD 9E 50
        call    PRINT_CR                                       ;#493D: CD B4 42
        ret                                                    ;#4940: C9

MEGA_PCMD_NEW:
        ; Prompt command "NEW" — clear source buffer (BASIC-style)
        call    PROMPT_TICK_TAIL_CHECK                         ;#4941: CD B5 41
RESET_SOURCE_BUFFER:
        ; Mid-NEW entry: set EC03 = EC01-1 (empty), clear MEGA_PASS1_DONE_FLAG
        ld      hl,(MEGA_SRC_BUF_START)                        ;#4944: 2A 01 EC
        dec     hl                                             ;#4947: 2B
        ld      (MEGA_SRC_BUF_HEAD),hl                         ;#4948: 22 03 EC
CLEAR_PASS1_DONE_FLAG:
        ; Tiny shared tail of RESET_SOURCE_BUFFER — zero MEGA_PASS1_DONE_FLAG and ret
        xor     a                                              ;#494B: AF
        ld      (MEGA_PASS1_DONE_FLAG),a                       ;#494C: 32 26 EC
        ret                                                    ;#494F: C9

SEARCH_REPORT_MATCH:
        ; Print the source line that contains the matched pattern
        call    MEGA_SLOT_READ_DE                              ;#4950: CD 1C FA
        inc     de                                             ;#4953: 13
        ld      l,a                                            ;#4954: 6F
        call    MEGA_SLOT_READ_DE                              ;#4955: CD 1C FA
        inc     de                                             ;#4958: 13
        ld      h,a                                            ;#4959: 67
        push    de                                             ;#495A: D5
        call    STORE_DEC_HL_TO_LINE                           ;#495B: CD A2 4F
        pop     de                                             ;#495E: D1
        ld      (hl)," "                                       ;#495F: 36 20
SEARCH_REPORT_COPY_LOOP:
        ; Per-byte body of SEARCH_REPORT_MATCH — copy bytes from src DE to dst HL until 0
        inc     hl                                             ;#4961: 23
        call    MEGA_SLOT_READ_DE                              ;#4962: CD 1C FA
        ld      (hl),a                                         ;#4965: 77
        inc     de                                             ;#4966: 13
        or      a                                              ;#4967: B7
        jr      nz,SEARCH_REPORT_COPY_LOOP                     ;#4968: 20 F7
        ld      (hl),"\r"                                      ;#496A: 36 0D
        ld      hl,MEGA_DISASM_LINE                            ;#496C: 21 C3 EC
        bit     3,(ix)                                         ;#496F: DD CB 00 5E
        jr      nz,SEARCH_REPORT_BUFFERED                      ;#4973: 20 0A
SEARCH_REPORT_PRINT_LOOP:
        ; Bit-3-clear printer: per-char PRINT_CHAR_DUAL from MEGA_DISASM_LINE until CR
        ld      a,(hl)                                         ;#4975: 7E
        inc     hl                                             ;#4976: 23
        call    PRINT_CHAR_DUAL                                ;#4977: CD C4 42
        cp      0Dh                                            ;#497A: FE 0D
        jr      nz,SEARCH_REPORT_PRINT_LOOP                    ;#497C: 20 F7
        ret                                                    ;#497E: C9

SEARCH_REPORT_BUFFERED:
        ; Bit-3-set: pre-inc HL then append bytes via MEGA_LIST_APPEND_BYTE (skips byte 0)
        inc     hl                                             ;#497F: 23
        ld      a,(hl)                                         ;#4980: 7E
        call    MEGA_LIST_APPEND_BYTE                          ;#4981: CD 5E 4A
        cp      0Dh                                            ;#4984: FE 0D
        jr      nz,SEARCH_REPORT_BUFFERED                      ;#4986: 20 F7
        ret                                                    ;#4988: C9

MEGA_PCMD_LLIST:
        ; Prompt command "LLIST" — set state bit 1 (printer echo) and fall into LIST
        set     1,(ix)                                         ;#4989: DD CB 00 CE
MEGA_PCMD_LIST:
        ; Prompt command "LIST" — full source listing with optional line-range args
        call    SKIP_SPACES_RAW                                ;#498D: CD 0E 5C
        or      a                                              ;#4990: B7
        jr      z,LIST_LINE_FETCH_LOOP                         ;#4991: 28 63
        call    PARSE_REQUIRED_LINE_NUMBER                     ;#4993: CD 79 50
        ld      (MEGA_AUTO_LINE_NUMBER),de                     ;#4996: ED 53 14 EC
        ld      (MEGA_AUTO_LINE_INCREMENT),de                  ;#499A: ED 53 16 EC
        ld      a,(hl)                                         ;#499E: 7E
        inc     hl                                             ;#499F: 23
        or      a                                              ;#49A0: B7
        ld      c,0                                            ;#49A1: 0E 00
        jr      z,LIST_RANGE_SETUP                             ;#49A3: 28 16
        ld      de,0FFFFh                                      ;#49A5: 11 FF FF
        ld      (MEGA_AUTO_LINE_INCREMENT),de                  ;#49A8: ED 53 16 EC
        call    SKIP_SPACES_RAW                                ;#49AC: CD 0E 5C
        or      a                                              ;#49AF: B7
        jr      z,LIST_END_FROM_PARSED                         ;#49B0: 28 07
        call    PARSE_REQUIRED_LINE_NUMBER                     ;#49B2: CD 79 50
        ld      (MEGA_AUTO_LINE_INCREMENT),de                  ;#49B5: ED 53 16 EC
LIST_END_FROM_PARSED:
        ; Second-arg present arm — set C=1 so LIST_RANGE_SETUP knows end is explicit
        ld      c,1                                            ;#49B9: 0E 01
LIST_RANGE_SETUP:
        ; Args parsed: LOCATE start, LOCATE end, fall into LIST_RANGE_LOOP
        push    bc                                             ;#49BB: C5
        ld      hl,(MEGA_AUTO_LINE_INCREMENT)                  ;#49BC: 2A 16 EC
        ld      (MEGA_LINE_NUMBER),hl                          ;#49BF: 22 0D EC
        call    LOCATE_LINE_BY_NUMBER                          ;#49C2: CD BF 4F
        ld      hl,(MEGA_SRC_LINE_PTR)                         ;#49C5: 2A 0B EC
        jr      nc,LIST_RANGE_STORE_END                        ;#49C8: 30 01
        dec     hl                                             ;#49CA: 2B
LIST_RANGE_STORE_END:
        ; Store end-of-range ptr after LOCATE_LINE_BY_NUMBER
        ld      (MEGA_LIST_LINE_PTR),hl                        ;#49CB: 22 18 EC
        ld      hl,(MEGA_AUTO_LINE_NUMBER)                     ;#49CE: 2A 14 EC
        ld      (MEGA_LINE_NUMBER),hl                          ;#49D1: 22 0D EC
        call    LOCATE_LINE_BY_NUMBER                          ;#49D4: CD BF 4F
        pop     bc                                             ;#49D7: C1
        ld      de,(MEGA_SRC_LINE_PTR)                         ;#49D8: ED 5B 0B EC
        dec     c                                              ;#49DC: 0D
        jr      z,LIST_RANGE_LOOP                              ;#49DD: 28 02
        jr      c,LIST_EXIT_TAIL_TRAP                          ;#49DF: 38 2F
LIST_RANGE_LOOP:
        ; LIST range walker (from..to) — stops at MEGA_LIST_LINE_PTR; reports each line
        call    FIND_SOURCE_LINE_BY_NUMBER                     ;#49E1: CD A7 4C
        call    nc,CHECK_USER_INTERRUPT                        ;#49E4: D4 9D 42
        jr      c,LIST_EXIT                                    ;#49E7: 38 1E
        ld      hl,(MEGA_LIST_LINE_PTR)                        ;#49E9: 2A 18 EC
        or      a                                              ;#49EC: B7
        sbc     hl,de                                          ;#49ED: ED 52
        jr      c,LIST_EXIT                                    ;#49EF: 38 16
        call    SEARCH_REPORT_MATCH                            ;#49F1: CD 50 49
        jr      LIST_RANGE_LOOP                                ;#49F4: 18 EB

LIST_LINE_FETCH_LOOP:
        ; Per-iteration body of LIST/SEARCH: refetch line by number, report match, loop
        ld      de,(MEGA_SRC_BUF_START)                        ;#49F6: ED 5B 01 EC
LIST_LINE_FETCH_NEXT:
        ; Re-enter per-iteration FIND_SOURCE_LINE_BY_NUMBER
        call    FIND_SOURCE_LINE_BY_NUMBER                     ;#49FA: CD A7 4C
        call    nc,CHECK_USER_INTERRUPT                        ;#49FD: D4 9D 42
        jr      c,LIST_EXIT                                    ;#4A00: 38 05
        call    SEARCH_REPORT_MATCH                            ;#4A02: CD 50 49
        jr      LIST_LINE_FETCH_NEXT                           ;#4A05: 18 F3

LIST_EXIT:
        ; LIST/RENUM exit: if (ix) bit 3 set, append tape EOF; else jp MEGA_PROMPT_TICK
        bit     3,(ix)                                         ;#4A07: DD CB 00 5E
        jr      nz,LIST_EXIT_TAPE_EOF                          ;#4A0B: 20 06
LIST_EXIT_PROMPT:
        ; Non-tape exit arm: jp MEGA_PROMPT_TICK
        jp      MEGA_PROMPT_TICK                               ;#4A0D: C3 19 41

LIST_EXIT_TAIL_TRAP:
        ; `jp SYNTAX_ERROR` filler — unreachable safety net wedged between LIST exit arms
        jp      SYNTAX_ERROR                                   ;#4A10: C3 B9 41

LIST_EXIT_TAPE_EOF:
        ; Tape branch: append 1Ah (EOF) and flush, then drop tape-mode bit, jp PROMPT_TICK
        ld      a,1Ah                                          ;#4A13: 3E 1A
        call    MEGA_LIST_APPEND_BYTE                          ;#4A15: CD 5E 4A
        call    TAPE_FLUSH_PENDING                             ;#4A18: CD 7B 4A
        res     3,(ix)                                         ;#4A1B: DD CB 00 9E
        jr      LIST_EXIT_PROMPT                               ;#4A1F: 18 EC

MEGA_SAVE_CASSETTE:
        ; Cassette branch of MEGA_PCMD_SAVE — parse `"name"`, set tape-mode, start TAPOON
        call    SKIP_SPACES_RAW                                ;#4A21: CD 0E 5C
        cp      '"'                                            ;#4A24: FE 22
        jp      nz,SYNTAX_ERROR                                ;#4A26: C2 B9 41
        inc     hl                                             ;#4A29: 23
        ld      a,(hl)                                         ;#4A2A: 7E
        cp      '"'                                            ;#4A2B: FE 22
        jp      z,SYNTAX_ERROR                                 ;#4A2D: CA B9 41
        call    INIT_TAPE_FILENAME                             ;#4A30: CD 57 4B
        set     3,(ix)                                         ;#4A33: DD CB 00 DE
        call    CASSETTE_TAPOON_AF                             ;#4A37: CD DD 42
        ld      b,1Eh                                          ;#4A3A: 06 1E
        ld      a,19h                                          ;#4A3C: 3E 19
SAVE_CAS_HDR_SYNC_LOOP:
        ; Per-byte body — emit 1Eh×19h sync header before SAVE filename
        call    CASSETTE_PUT_BYTE                              ;#4A3E: CD FB 42
        djnz    SAVE_CAS_HDR_SYNC_LOOP                         ;#4A41: 10 FB
        ld      a,9Ch                                          ;#4A43: 3E 9C
        call    CASSETTE_PUT_BYTE                              ;#4A45: CD FB 42
        ld      hl,MEGA_LIST_BUF                               ;#4A48: 21 16 EE
        ld      b,10h                                          ;#4A4B: 06 10
SAVE_CAS_FILENAME_LOOP:
        ; Per-byte body — write 16 bytes of MEGA_LIST_BUF (filename) to cassette
        ld      a,(hl)                                         ;#4A4D: 7E
        call    CASSETTE_PUT_BYTE                              ;#4A4E: CD FB 42
        inc     hl                                             ;#4A51: 23
        djnz    SAVE_CAS_FILENAME_LOOP                         ;#4A52: 10 F9
        call    CASSETTE_STOP_WRITE                            ;#4A54: CD 3E 43
        xor     a                                              ;#4A57: AF
        ld      (MEGA_LIST_BUF_COUNT),a                        ;#4A58: 32 6A EC
        jp      LIST_LINE_FETCH_LOOP                           ;#4A5B: C3 F6 49

MEGA_LIST_APPEND_BYTE:
        ; Append A to MEGA_LIST_BUF[MEGA_LIST_BUF_COUNT++]; flush when count wraps
        push    af                                             ;#4A5E: F5
        push    hl                                             ;#4A5F: E5
        push    de                                             ;#4A60: D5
        push    bc                                             ;#4A61: C5
        ld      c,a                                            ;#4A62: 4F
        ld      a,(MEGA_LIST_BUF_COUNT)                        ;#4A63: 3A 6A EC
        ld      e,a                                            ;#4A66: 5F
        ld      d,0                                            ;#4A67: 16 00
        ld      hl,MEGA_LIST_BUF                               ;#4A69: 21 16 EE
        add     hl,de                                          ;#4A6C: 19
        ld      (hl),c                                         ;#4A6D: 71
        ld      a,e                                            ;#4A6E: 7B
        inc     a                                              ;#4A6F: 3C
        ld      (MEGA_LIST_BUF_COUNT),a                        ;#4A70: 32 6A EC
        call    z,TAPE_FLUSH_LIST_BUF                          ;#4A73: CC 80 4A
        pop     bc                                             ;#4A76: C1
        pop     de                                             ;#4A77: D1
        pop     hl                                             ;#4A78: E1
        pop     af                                             ;#4A79: F1
        ret                                                    ;#4A7A: C9

TAPE_FLUSH_PENDING:
        ; ret if MEGA_LIST_BUF_COUNT=0; else fall into TAPE_FLUSH_LIST_BUF
        ld      a,(MEGA_LIST_BUF_COUNT)                        ;#4A7B: 3A 6A EC
        or      a                                              ;#4A7E: B7
        ret     z                                              ;#4A7F: C8
TAPE_FLUSH_LIST_BUF:
        ; Emit MEGA_LIST_BUF (256 bytes at EE16h) to cassette with the 1Eh×18h+9Ch header
        call    CASSETTE_TAPOON_AF                             ;#4A80: CD DD 42
        ld      b,1Eh                                          ;#4A83: 06 1E
        ld      a,18h                                          ;#4A85: 3E 18
TAPE_FLUSH_HDR_SYNC_LOOP:
        ; Per-byte body — emit 1Eh×18h sync header before list-buf flush
        call    CASSETTE_PUT_BYTE                              ;#4A87: CD FB 42
        djnz    TAPE_FLUSH_HDR_SYNC_LOOP                       ;#4A8A: 10 FB
        ld      a,9Ch                                          ;#4A8C: 3E 9C
        call    CASSETTE_PUT_BYTE                              ;#4A8E: CD FB 42
        ld      hl,MEGA_LIST_BUF                               ;#4A91: 21 16 EE
        ld      c,0                                            ;#4A94: 0E 00
        ld      b,0                                            ;#4A96: 06 00
TAPE_FLUSH_BUFFER_LOOP:
        ; Per-byte body of TAPE_FLUSH_LIST_BUF — emit byte to tape, sum into checksum C
        ld      a,(hl)                                         ;#4A98: 7E
        inc     hl                                             ;#4A99: 23
        call    CASSETTE_PUT_BYTE                              ;#4A9A: CD FB 42
        add     a,c                                            ;#4A9D: 81
        ld      c,a                                            ;#4A9E: 4F
        djnz    TAPE_FLUSH_BUFFER_LOOP                         ;#4A9F: 10 F7
        ld      a,c                                            ;#4AA1: 79
        call    CASSETTE_PUT_BYTE                              ;#4AA2: CD FB 42
        jp      CASSETTE_STOP_WRITE                            ;#4AA5: C3 3E 43

MERGE_APPEND_ENTRY:
        ; Set state bit 2 (append-mode) then fall into MEGA_PCMD_MERGE
        set     2,(ix)                                         ;#4AA8: DD CB 00 D6
MEGA_PCMD_MERGE:
        ; Prompt command "MERGE" — merge file into source
        call    SKIP_SPACES_RAW                                ;#4AAC: CD 0E 5C
        cp      '"'                                            ;#4AAF: FE 22
        jp      nz,SYNTAX_ERROR                                ;#4AB1: C2 B9 41
        xor     a                                              ;#4AB4: AF
        ld      (MEGA_LINE_RANGE_END),a                        ;#4AB5: 32 22 EC
        inc     hl                                             ;#4AB8: 23
        ld      a,(hl)                                         ;#4AB9: 7E
        cp      '"'                                            ;#4ABA: FE 22
        jr      nz,MEGA_PCMD_MERGE_PREP                        ;#4ABC: 20 03
        ld      (MEGA_LINE_RANGE_END),a                        ;#4ABE: 32 22 EC
MEGA_PCMD_MERGE_PREP:
        ; Common prep: INIT_TAPE_FILENAME, set state bit 3, fall into MERGE_TAPE_FILE_SCAN
        call    INIT_TAPE_FILENAME                             ;#4AC1: CD 57 4B
        set     3,(ix)                                         ;#4AC4: DD CB 00 DE
MERGE_TAPE_FILE_SCAN:
        ; Inner loop of MEGA_PCMD_MERGE — read tape header, match expected filename, retry
        call    CASSETTE_START_READ                            ;#4AC8: CD 11 43
        ld      hl,MEGA_TAPE_HDR_FILENAME                      ;#4ACB: 21 27 EE
        ld      b,10h                                          ;#4ACE: 06 10
MERGE_HEADER_FILL_LOOP:
        ; Clear filename buffer EE27h..EE36h to spaces before header read
        ld      (hl)," "                                       ;#4AD0: 36 20
        inc     hl                                             ;#4AD2: 23
        djnz    MERGE_HEADER_FILL_LOOP                         ;#4AD3: 10 FB
        ld      (hl),"\r"                                      ;#4AD5: 36 0D
MERGE_HEADER_SYNC_WAIT:
        ; Read 14h sync bytes — restart if any is not 19h
        ld      b,14h                                          ;#4AD7: 06 14
MERGE_HDR_SYNC_COUNT_LOOP:
        ; Per-byte body — count 14h consecutive 19h sync bytes on read
        call    CASSETTE_GET_BYTE                              ;#4AD9: CD 26 43
        cp      19h                                            ;#4ADC: FE 19
        jr      nz,MERGE_HEADER_SYNC_WAIT                      ;#4ADE: 20 F7
        djnz    MERGE_HDR_SYNC_COUNT_LOOP                      ;#4AE0: 10 F7
MERGE_HEADER_SYNC_DRAIN:
        ; Drain extra 19h sync padding after the run-of-20 completes
        call    CASSETTE_GET_BYTE                              ;#4AE2: CD 26 43
        cp      19h                                            ;#4AE5: FE 19
        jr      z,MERGE_HEADER_SYNC_DRAIN                      ;#4AE7: 28 F9
        ld      hl,MEGA_TAPE_HDR_FILENAME                      ;#4AE9: 21 27 EE
        ld      b,10h                                          ;#4AEC: 06 10
MERGE_HDR_FILENAME_LOOP:
        ; Per-byte body — read 16-byte tape filename into EE27h
        call    CASSETTE_GET_BYTE                              ;#4AEE: CD 26 43
        ld      (hl),a                                         ;#4AF1: 77
        inc     hl                                             ;#4AF2: 23
        djnz    MERGE_HDR_FILENAME_LOOP                        ;#4AF3: 10 F9
        call    CASSETTE_STOP_READ                             ;#4AF5: CD 32 43
        ld      a,(MEGA_LINE_RANGE_END)                        ;#4AF8: 3A 22 EC
        or      a                                              ;#4AFB: B7
        jr      nz,MERGE_TAPE_FILE_FOUND                       ;#4AFC: 20 16
        call    MATCH_TAPE_FILENAME                            ;#4AFE: CD 46 4B
        jr      z,MERGE_TAPE_FILE_FOUND                        ;#4B01: 28 11
        call    PRINT_PULEI_PREFIX                             ;#4B03: CD CC 58
        nop                                                    ;#4B06: 00
        nop                                                    ;#4B07: 00
        nop                                                    ;#4B08: 00
        nop                                                    ;#4B09: 00
        nop                                                    ;#4B0A: 00
        nop                                                    ;#4B0B: 00
        ld      hl,MEGA_TAPE_HDR_FILENAME                      ;#4B0C: 21 27 EE
        call    PRINT_CR_STRING                                ;#4B0F: CD 3C 4B
        jr      MERGE_TAPE_FILE_SCAN                           ;#4B12: 18 B4

MERGE_TAPE_FILE_FOUND:
        ; Filename matched or wildcard mode: print "Achei:" + name, fall into load
        call    PRINT_ACHEI_PREFIX                             ;#4B14: CD 7D 5C
        nop                                                    ;#4B17: 00
        nop                                                    ;#4B18: 00
        nop                                                    ;#4B19: 00
        nop                                                    ;#4B1A: 00
        nop                                                    ;#4B1B: 00
        nop                                                    ;#4B1C: 00
        ld      hl,MEGA_TAPE_HDR_FILENAME                      ;#4B1D: 21 27 EE
        call    PRINT_CR_STRING                                ;#4B20: CD 3C 4B
        xor     a                                              ;#4B23: AF
        ld      (MEGA_LIST_BUF_COUNT),a                        ;#4B24: 32 6A EC
        ld      hl,(MEGA_SRC_BUF_START)                        ;#4B27: 2A 01 EC
        ld      (MEGA_SRC_LINE_PTR),hl                         ;#4B2A: 22 0B EC
        bit     2,(ix)                                         ;#4B2D: DD CB 00 56
        call    nz,RESET_SOURCE_BUFFER                         ;#4B31: C4 44 49
        res     2,(ix)                                         ;#4B34: DD CB 00 96
        pop     bc                                             ;#4B38: C1
        jp      PROMPT_TICK_READ_LINE                          ;#4B39: C3 42 41

PRINT_CR_STRING:
        ; Walk (HL), echo each byte via PRINT_CHAR until a CR (0Dh) is printed
        ld      a,(hl)                                         ;#4B3C: 7E
        inc     hl                                             ;#4B3D: 23
        call    PRINT_CHAR                                     ;#4B3E: CD B6 42
        cp      0Dh                                            ;#4B41: FE 0D
        jr      nz,PRINT_CR_STRING                             ;#4B43: 20 F7
        ret                                                    ;#4B45: C9

MATCH_TAPE_FILENAME:
        ; Compare 16 bytes of MEGA_LIST_BUF against EE27 (expected tape filename)
        ld      hl,MEGA_LIST_BUF                               ;#4B46: 21 16 EE
        ld      de,MEGA_TAPE_HDR_FILENAME                      ;#4B49: 11 27 EE
        ld      b,10h                                          ;#4B4C: 06 10
MATCH_TAPE_FILENAME_LOOP:
        ; Per-byte body — compare 16 filename bytes (DE) vs (HL)
        ld      a,(de)                                         ;#4B4E: 1A
        cp      (hl)                                           ;#4B4F: BE
        jr      nz,MATCH_TAPE_FILENAME_END                     ;#4B50: 20 04
        inc     hl                                             ;#4B52: 23
        inc     de                                             ;#4B53: 13
        djnz    MATCH_TAPE_FILENAME_LOOP                       ;#4B54: 10 F8
MATCH_TAPE_FILENAME_END:
        ; Bare `ret` — common tail of MATCH_TAPE_FILENAME (Z=match, NZ=mismatch)
        ret                                                    ;#4B56: C9

INIT_TAPE_FILENAME:
        ; Fill 16-byte filename buffer at EE16h with spaces, then write CR at byte 16
        ld      de,MEGA_LIST_BUF                               ;#4B57: 11 16 EE
        ld      b,10h                                          ;#4B5A: 06 10
        ld      a," "                                          ;#4B5C: 3E 20
INIT_TAPE_FILENAME_LOOP:
        ; Per-byte body — fill 16-byte filename buffer with spaces
        ld      (de),a                                         ;#4B5E: 12
        inc     de                                             ;#4B5F: 13
        djnz    INIT_TAPE_FILENAME_LOOP                        ;#4B60: 10 FC
        ld      a,"\r"                                         ;#4B62: 3E 0D
        ld      (de),a                                         ;#4B64: 12
        ld      de,MEGA_LIST_BUF                               ;#4B65: 11 16 EE
        ld      b,10h                                          ;#4B68: 06 10
COPY_TAPE_FILENAME:
        ; Copy filename from HL into MEGA_LIST_BUF (up to 16 chars, stop on NUL or `"`)
        ld      a,(hl)                                         ;#4B6A: 7E
        inc     hl                                             ;#4B6B: 23
        or      a                                              ;#4B6C: B7
        jr      z,COPY_TAPE_FILENAME_END                       ;#4B6D: 28 08
        cp      '"'                                            ;#4B6F: FE 22
        jr      z,COPY_TAPE_FILENAME_END                       ;#4B71: 28 04
        ld      (de),a                                         ;#4B73: 12
        inc     de                                             ;#4B74: 13
        djnz    COPY_TAPE_FILENAME                             ;#4B75: 10 F3
COPY_TAPE_FILENAME_END:
        ; Bare `ret` — end of COPY_TAPE_FILENAME (NUL or `"` reached, or 16 chars copied)
        ret                                                    ;#4B77: C9

TAPE_DELAY_16:
        ; Tape-timing delay: 16 × 0A000h-iteration busy loop (longest variant)
        ld      e,10h                                          ;#4B78: 1E 10
        jr      TAPE_DELAY_LOOP                                ;#4B7A: 18 0A

TAPE_DELAY_8:
        ; Tape-timing delay: 8 × 0A000h-iteration busy loop
        ld      e,8                                            ;#4B7C: 1E 08
        jr      TAPE_DELAY_LOOP                                ;#4B7E: 18 06

TAPE_DELAY_2:
        ; Tape-timing delay: 2 × 0A000h-iteration busy loop (most-used variant)
        ld      e,2                                            ;#4B80: 1E 02
        jr      TAPE_DELAY_LOOP                                ;#4B82: 18 02

TAPE_DELAY_1:
        ; Tape-timing delay: 1 × 0A000h-iteration busy loop (shortest)
        ld      e,1                                            ;#4B84: 1E 01
TAPE_DELAY_LOOP:
        ; Shared inner loop: E × 0A000h dec-bc busy iterations (TAPE_DELAY_* trampolines)
        ld      bc,0A000h                                      ;#4B86: 01 00 A0
TAPE_DELAY_INNER:
        ; Inner countdown body of TAPE_DELAY_LOOP — dec BC, loop until BC=0
        dec     bc                                             ;#4B89: 0B
        ld      a,b                                            ;#4B8A: 78
        or      c                                              ;#4B8B: B1
        jr      nz,TAPE_DELAY_INNER                            ;#4B8C: 20 FB
        dec     e                                              ;#4B8E: 1D
        jr      nz,TAPE_DELAY_LOOP                             ;#4B8F: 20 F5
        ret                                                    ;#4B91: C9

READ_INPUT_LINE:
        ; Line editor — reads one prompt line into the buffer pointed by F9FE
        bit     3,(ix)                                         ;#4B92: DD CB 00 5E
        jp      z,INPUT_LINE_FROM_KBD                          ;#4B96: CA 8A 42
        ld      hl,(MEGA_INPUT_LINE_PTR)                       ;#4B99: 2A FE F9
        ld      b,0FFh                                         ;#4B9C: 06 FF
INPUT_LINE_READ_LOOP:
        ; Per-byte loop body of READ_INPUT_LINE — fetch via BUF_GET_BYTE, dispatch
        call    TAPE_BUF_GET_BYTE                              ;#4B9E: CD BC 4B
        cp      1Ah                                            ;#4BA1: FE 1A
        jr      z,INPUT_LINE_EOF                               ;#4BA3: 28 10
        cp      0Dh                                            ;#4BA5: FE 0D
        jr      z,INPUT_LINE_CR                                ;#4BA7: 28 09
        inc     b                                              ;#4BA9: 04
        dec     b                                              ;#4BAA: 05
        jr      z,INPUT_LINE_READ_LOOP                         ;#4BAB: 28 F1
        ld      (hl),a                                         ;#4BAD: 77
        inc     hl                                             ;#4BAE: 23
        dec     b                                              ;#4BAF: 05
        jr      INPUT_LINE_READ_LOOP                           ;#4BB0: 18 EC

INPUT_LINE_CR:
        ; CR (0Dh) found: write NUL terminator at (hl), ret to caller
        ld      (hl),0                                         ;#4BB2: 36 00
        ret                                                    ;#4BB4: C9

INPUT_LINE_EOF:
        ; EOF (1Ah) found: clear bit 3 of (ix), jp MEGA_PROMPT_TICK (no return)
        res     3,(ix)                                         ;#4BB5: DD CB 00 9E
        jp      MEGA_PROMPT_TICK                               ;#4BB9: C3 19 41

TAPE_BUF_GET_BYTE:
        ; Buffered tape byte read — refills MEGA_LIST_BUF via TAPE_BUF_REFILL when empty
        ld      a,(MEGA_LIST_BUF_COUNT)                        ;#4BBC: 3A 6A EC
        or      a                                              ;#4BBF: B7
        jr      nz,TAPE_BUF_GET_BYTE_HAS                       ;#4BC0: 20 04
        call    TAPE_BUF_REFILL                                ;#4BC2: CD D8 4B
        xor     a                                              ;#4BC5: AF
TAPE_BUF_GET_BYTE_HAS:
        ; Buffer non-empty (or just refilled) — read MEGA_LIST_BUF[count-1] into A
        inc     a                                              ;#4BC6: 3C
        ld      (MEGA_LIST_BUF_COUNT),a                        ;#4BC7: 32 6A EC
        push    hl                                             ;#4BCA: E5
        push    de                                             ;#4BCB: D5
        dec     a                                              ;#4BCC: 3D
        ld      e,a                                            ;#4BCD: 5F
        ld      d,0                                            ;#4BCE: 16 00
        ld      hl,MEGA_LIST_BUF                               ;#4BD0: 21 16 EE
        add     hl,de                                          ;#4BD3: 19
        ld      a,(hl)                                         ;#4BD4: 7E
        pop     de                                             ;#4BD5: D1
        pop     hl                                             ;#4BD6: E1
        ret                                                    ;#4BD7: C9

TAPE_BUF_REFILL:
        ; Refill MEGA_LIST_BUF (256 bytes) from cassette with the 14h×18h+9Ch header dance
        push    hl                                             ;#4BD8: E5
        push    de                                             ;#4BD9: D5
        push    bc                                             ;#4BDA: C5
        call    CASSETTE_START_READ                            ;#4BDB: CD 11 43
TAPE_BUF_REFILL_SYNC:
        ; 18h sync-byte wait — count 14h consecutive 18h before accepting header
        ld      b,14h                                          ;#4BDE: 06 14
TAPE_BUF_REFILL_SYNC_COUNT:
        ; Per-byte body — count 14h consecutive 18h sync bytes on read
        call    CASSETTE_GET_BYTE                              ;#4BE0: CD 26 43
        cp      18h                                            ;#4BE3: FE 18
        jr      nz,TAPE_BUF_REFILL_SYNC                        ;#4BE5: 20 F7
        djnz    TAPE_BUF_REFILL_SYNC_COUNT                     ;#4BE7: 10 F7
TAPE_BUF_REFILL_DRAIN:
        ; Drain extra 18h padding after the run-of-20 completes
        call    CASSETTE_GET_BYTE                              ;#4BE9: CD 26 43
        cp      18h                                            ;#4BEC: FE 18
        jr      z,TAPE_BUF_REFILL_DRAIN                        ;#4BEE: 28 F9
        ld      hl,MEGA_LIST_BUF                               ;#4BF0: 21 16 EE
        ld      c,0                                            ;#4BF3: 0E 00
        ld      b,0                                            ;#4BF5: 06 00
TAPE_BUF_REFILL_BYTE_LOOP:
        ; Per-byte body — read 256 bytes into MEGA_LIST_BUF, sum into C
        call    CASSETTE_GET_BYTE                              ;#4BF7: CD 26 43
        ld      (hl),a                                         ;#4BFA: 77
        inc     hl                                             ;#4BFB: 23
        add     a,c                                            ;#4BFC: 81
        ld      c,a                                            ;#4BFD: 4F
        djnz    TAPE_BUF_REFILL_BYTE_LOOP                      ;#4BFE: 10 F7
        call    CASSETTE_GET_BYTE                              ;#4C00: CD 26 43
        cp      c                                              ;#4C03: B9
        push    af                                             ;#4C04: F5
        call    TAPE_DELAY_1                                   ;#4C05: CD 84 4B
        call    CASSETTE_STOP_READ                             ;#4C08: CD 32 43
        pop     af                                             ;#4C0B: F1
        pop     bc                                             ;#4C0C: C1
        pop     de                                             ;#4C0D: D1
        pop     hl                                             ;#4C0E: E1
        ret     z                                              ;#4C0F: C8
        jp      CASSETTE_RESTORE_RAISE                         ;#4C10: C3 23 43

MEGA_PCMD_LSEARCH:
        ; Prompt command "LSEARCH" — set state bit 1 (printer echo) then fall into SEARCH
        set     1,(ix)                                         ;#4C13: DD CB 00 CE
MEGA_PCMD_SEARCH:
        ; Prompt command "SEARCH" — locate text in source, optional printer echo
        call    SEARCH_PARSE_PATTERN                           ;#4C17: CD 92 4C
        ld      a,(hl)                                         ;#4C1A: 7E
        or      a                                              ;#4C1B: B7
        jr      z,MEGA_PCMD_SEARCH_DONE                        ;#4C1C: 28 2F
        ld      (MEGA_SEARCH_PATTERN),hl                       ;#4C1E: 22 1A EC
        ld      de,(MEGA_SRC_BUF_START)                        ;#4C21: ED 5B 01 EC
SEARCH_LINE_LOOP:
        ; Per-line loop of SEARCH: locate line, scan with STRING_MATCH, report all matches
        call    FIND_SOURCE_LINE_BY_NUMBER                     ;#4C25: CD A7 4C
        call    nc,CHECK_USER_INTERRUPT                        ;#4C28: D4 9D 42
        jr      c,MEGA_PCMD_SEARCH_DONE                        ;#4C2B: 38 20
        push    de                                             ;#4C2D: D5
        inc     de                                             ;#4C2E: 13
        inc     de                                             ;#4C2F: 13
SEARCH_SCAN_CHAR_LOOP:
        ; Per-char scan within source line for STRING_MATCH
        push    de                                             ;#4C30: D5
        ld      hl,(MEGA_SEARCH_PATTERN)                       ;#4C31: 2A 1A EC
        call    STRING_MATCH                                   ;#4C34: CD 83 4C
        pop     de                                             ;#4C37: D1
        jr      c,MEGA_PCMD_SEARCH_REPORT                      ;#4C38: 38 0B
        inc     de                                             ;#4C3A: 13
        jr      nz,SEARCH_SCAN_CHAR_LOOP                       ;#4C3B: 20 F3
        pop     de                                             ;#4C3D: D1
SEARCH_NEXT_LINE:
        ; Advance to next source line and re-enter SEARCH_LINE_LOOP
        ex      de,hl                                          ;#4C3E: EB
        call    NEXT_SOURCE_LINE                               ;#4C3F: CD FB 4F
        ex      de,hl                                          ;#4C42: EB
        jr      SEARCH_LINE_LOOP                               ;#4C43: 18 E0

MEGA_PCMD_SEARCH_REPORT:
        ; Match in current line: SEARCH_REPORT_MATCH then continue scanning line
        pop     de                                             ;#4C45: D1
        push    de                                             ;#4C46: D5
        call    SEARCH_REPORT_MATCH                            ;#4C47: CD 50 49
        pop     de                                             ;#4C4A: D1
        jr      SEARCH_NEXT_LINE                               ;#4C4B: 18 F1

MEGA_PCMD_SEARCH_DONE:
        ; Exit path — jp MEGA_PROMPT_TICK (no pattern, EOF, or user interrupt)
        jp      MEGA_PROMPT_TICK                               ;#4C4D: C3 19 41

MEGA_PCMD_FIND:
        ; Prompt command "FIND" — find first match of text in source
        call    SEARCH_PARSE_PATTERN                           ;#4C50: CD 92 4C
        ld      a,(hl)                                         ;#4C53: 7E
        or      a                                              ;#4C54: B7
        jr      z,MEGA_PCMD_FIND_DONE                          ;#4C55: 28 29
        ld      (MEGA_SEARCH_PATTERN),hl                       ;#4C57: 22 1A EC
        ld      de,(MEGA_SRC_BUF_START)                        ;#4C5A: ED 5B 01 EC
FIND_LINE_LOOP:
        ; Per-line loop of FIND: locate line, scan with STRING_MATCH, exit on first hit
        call    FIND_SOURCE_LINE_BY_NUMBER                     ;#4C5E: CD A7 4C
        call    nc,CHECK_USER_INTERRUPT                        ;#4C61: D4 9D 42
        jr      c,MEGA_PCMD_FIND_DONE                          ;#4C64: 38 1A
        push    de                                             ;#4C66: D5
        inc     de                                             ;#4C67: 13
        inc     de                                             ;#4C68: 13
        ld      hl,(MEGA_SEARCH_PATTERN)                       ;#4C69: 2A 1A EC
        call    STRING_MATCH                                   ;#4C6C: CD 83 4C
        pop     de                                             ;#4C6F: D1
        jr      c,MEGA_PCMD_FIND_REPORT                        ;#4C70: 38 07
FIND_NEXT_LINE:
        ; Advance to next source line and re-enter FIND_LINE_LOOP
        ex      de,hl                                          ;#4C72: EB
        call    NEXT_SOURCE_LINE                               ;#4C73: CD FB 4F
        ex      de,hl                                          ;#4C76: EB
        jr      FIND_LINE_LOOP                                 ;#4C77: 18 E5

MEGA_PCMD_FIND_REPORT:
        ; Match found: SEARCH_REPORT_MATCH then continue scanning at FIND_NEXT_LINE
        push    de                                             ;#4C79: D5
        call    SEARCH_REPORT_MATCH                            ;#4C7A: CD 50 49
        pop     de                                             ;#4C7D: D1
        jr      FIND_NEXT_LINE                                 ;#4C7E: 18 F2

MEGA_PCMD_FIND_DONE:
        ; Exit path — jp MEGA_PROMPT_TICK (no pattern, EOF, or user interrupt)
        jp      MEGA_PROMPT_TICK                               ;#4C80: C3 19 41

STRING_MATCH:
        ; Compare pattern at HL against source bytes at DE; CF=1 = match, NC = miss
        call    MEGA_SLOT_READ_DE                              ;#4C83: CD 1C FA
        or      a                                              ;#4C86: B7
        ret     z                                              ;#4C87: C8
        xor     (hl)                                           ;#4C88: AE
        ret     nz                                             ;#4C89: C0
        inc     hl                                             ;#4C8A: 23
        inc     de                                             ;#4C8B: 13
        ld      a,(hl)                                         ;#4C8C: 7E
        or      a                                              ;#4C8D: B7
        jr      nz,STRING_MATCH                                ;#4C8E: 20 F3
        scf                                                    ;#4C90: 37
        ret                                                    ;#4C91: C9

SEARCH_PARSE_PATTERN:
        ; Parse a search/find pattern from the user input line into a temp buffer
        push    hl                                             ;#4C92: E5
SEARCH_PARSE_PATTERN_LOOP:
        ; Per-char loop body: read next byte, advance HL, check for `|` or NUL
        ld      a,(hl)                                         ;#4C93: 7E
        inc     hl                                             ;#4C94: 23
        cp      "|"                                            ;#4C95: FE 7C
        jr      z,SEARCH_PARSE_PATTERN_PIPE                    ;#4C97: 28 05
        or      a                                              ;#4C99: B7
        jr      nz,SEARCH_PARSE_PATTERN_LOOP                   ;#4C9A: 20 F7
        jr      SEARCH_PARSE_PATTERN_DONE                      ;#4C9C: 18 07

SEARCH_PARSE_PATTERN_PIPE:
        ; After `|` terminator: walk to NUL then null-terminate the pattern in place
        ld      a,(hl)                                         ;#4C9E: 7E
        or      a                                              ;#4C9F: B7
        jr      nz,SEARCH_PARSE_PATTERN_LOOP                   ;#4CA0: 20 F1
        dec     hl                                             ;#4CA2: 2B
        ld      (hl),0                                         ;#4CA3: 36 00
SEARCH_PARSE_PATTERN_DONE:
        ; Restore HL and return from pattern parser
        pop     hl                                             ;#4CA5: E1
        ret                                                    ;#4CA6: C9

FIND_SOURCE_LINE_BY_NUMBER:
        ; Walk source buffer for a line whose number ≥ (MEGA_LINE_NUMBER)
        push    hl                                             ;#4CA7: E5
        ld      hl,(MEGA_SRC_BUF_HEAD)                         ;#4CA8: 2A 03 EC
        or      a                                              ;#4CAB: B7
        sbc     hl,de                                          ;#4CAC: ED 52
        pop     hl                                             ;#4CAE: E1
        ret                                                    ;#4CAF: C9

MEGA_PCMD_CHANGE:
        ; Prompt command "CHANGE" — `CHANGE/old/new/` search-and-replace
        ld      d,(hl)                                         ;#4CB0: 56
        call    MEGA_PCMD_F_BODY                               ;#4CB1: CD 38 6B
        nop                                                    ;#4CB4: 00
        dec     hl                                             ;#4CB5: 2B
        ld      bc,0FFFFh                                      ;#4CB6: 01 FF FF
CHANGE_SEP_FIND_LOOP:
        ; Walk input looking for the `/` separator (delimits old from new pattern)
        inc     hl                                             ;#4CB9: 23
        ld      a,(hl)                                         ;#4CBA: 7E
        or      a                                              ;#4CBB: B7
        jr      z,CHANGE_SEP_OK_CHECK                          ;#4CBC: 28 06
        inc     bc                                             ;#4CBE: 03
        cp      d                                              ;#4CBF: BA
        jr      nz,CHANGE_SEP_FIND_LOOP                        ;#4CC0: 20 F7
        ld      a,b                                            ;#4CC2: 78
        or      c                                              ;#4CC3: B1
CHANGE_SEP_OK_CHECK:
        ; Validate sep found at least once: BC=0 → CHANGE_NOT_FOUND
        jp      z,CHANGE_NOT_FOUND                             ;#4CC4: CA 6E 4D
        ld      (hl),0                                         ;#4CC7: 36 00
        inc     hl                                             ;#4CC9: 23
        ld      (MEGA_CHANGE_REPLACE),hl                       ;#4CCA: 22 1C EC
        ld      de,(MEGA_SRC_BUF_START)                        ;#4CCD: ED 5B 01 EC
CHANGE_LINE_LOOP:
        ; Per-source-line outer loop of CHANGE — clear MEGA_CHANGE_FOUND, walk positions
        ld      (MEGA_SRC_LINE_PTR),de                         ;#4CD1: ED 53 0B EC
        call    FIND_SOURCE_LINE_BY_NUMBER                     ;#4CD5: CD A7 4C
        call    nc,CHECK_USER_INTERRUPT                        ;#4CD8: D4 9D 42
        jp      c,CHANGE_DONE                                  ;#4CDB: DA 71 4D
        xor     a                                              ;#4CDE: AF
        ld      (MEGA_CHANGE_FOUND),a                          ;#4CDF: 32 25 EC
        inc     de                                             ;#4CE2: 13
        inc     de                                             ;#4CE3: 13
        ld      hl,MEGA_CHANGE_TARGET                          ;#4CE4: 21 18 EE
CHANGE_MATCH_POS_LOOP:
        ; Inner per-position loop: STRING_MATCH; on hit, materialize replacement
        ld      (MEGA_CHANGE_SRC_PTR),de                       ;#4CE7: ED 53 1E EC
        ld      (MEGA_CHANGE_DST_PTR),hl                       ;#4CEB: 22 20 EC
CHANGE_MATCH_POS_INNER:
        ; Per-position pattern match inside the line — push DE, STRING_MATCH, branch
        push    de                                             ;#4CEE: D5
        ld      hl,(MEGA_SEARCH_PATTERN)                       ;#4CEF: 2A 1A EC
        call    STRING_MATCH                                   ;#4CF2: CD 83 4C
        jr      c,CHANGE_MATCH_HIT                             ;#4CF5: 38 13
        pop     de                                             ;#4CF7: D1
        inc     de                                             ;#4CF8: 13
        jr      nz,CHANGE_MATCH_POS_INNER                      ;#4CF9: 20 F3
        ld      a,(MEGA_CHANGE_FOUND)                          ;#4CFB: 3A 25 EC
        or      a                                              ;#4CFE: B7
        jr      nz,CHANGE_COPY_SUFFIX_ENTRY                    ;#4CFF: 20 38
CHANGE_NEXT_LINE:
        ; Advance source pointer and re-enter CHANGE_LINE_LOOP
        ld      hl,(MEGA_SRC_LINE_PTR)                         ;#4D01: 2A 0B EC
        call    NEXT_SOURCE_LINE                               ;#4D04: CD FB 4F
        ex      de,hl                                          ;#4D07: EB
        jr      CHANGE_LINE_LOOP                               ;#4D08: 18 C7

CHANGE_MATCH_HIT:
        ; Match found: set MEGA_CHANGE_FOUND=FFh, prepare BC=src/DE=dst for copies
        ld      a,0FFh                                         ;#4D0A: 3E FF
        ld      (MEGA_CHANGE_FOUND),a                          ;#4D0C: 32 25 EC
        ex      de,hl                                          ;#4D0F: EB
        ex      (sp),hl                                        ;#4D10: E3
        ld      bc,(MEGA_CHANGE_SRC_PTR)                       ;#4D11: ED 4B 1E EC
        ld      de,(MEGA_CHANGE_DST_PTR)                       ;#4D15: ED 5B 20 EC
CHANGE_COPY_PREFIX_LOOP:
        ; Copy bytes from CHANGE_SRC_PTR to DST_PTR until SRC reaches the match position
        ld      a,c                                            ;#4D19: 79
        cp      l                                              ;#4D1A: BD
        jr      z,CHANGE_COPY_REPLACE_ENTRY                    ;#4D1B: 28 0C
        push    hl                                             ;#4D1D: E5
        ld      h,b                                            ;#4D1E: 60
        ld      l,c                                            ;#4D1F: 69
        call    MEGA_SLOT_READ_HL                              ;#4D20: CD 16 FA
        pop     hl                                             ;#4D23: E1
        ld      (de),a                                         ;#4D24: 12
        inc     bc                                             ;#4D25: 03
        inc     de                                             ;#4D26: 13
        jr      CHANGE_COPY_PREFIX_LOOP                        ;#4D27: 18 F0

CHANGE_COPY_REPLACE_ENTRY:
        ; Prefix copied — load REPLACE pointer and fall into _REPLACE_LOOP
        ld      hl,(MEGA_CHANGE_REPLACE)                       ;#4D29: 2A 1C EC
CHANGE_COPY_REPLACE_LOOP:
        ; Copy the MEGA_CHANGE_REPLACE replacement string into DST until NUL
        ld      a,(hl)                                         ;#4D2C: 7E
        or      a                                              ;#4D2D: B7
        jr      z,CHANGE_COPY_REPLACE_END                      ;#4D2E: 28 05
        ld      (de),a                                         ;#4D30: 12
        inc     hl                                             ;#4D31: 23
        inc     de                                             ;#4D32: 13
        jr      CHANGE_COPY_REPLACE_LOOP                       ;#4D33: 18 F7

CHANGE_COPY_REPLACE_END:
        ; Replace done — ex de,hl; pop saved DE; jr CHANGE_MATCH_POS_LOOP for next pos
        ex      de,hl                                          ;#4D35: EB
        pop     de                                             ;#4D36: D1
        jr      CHANGE_MATCH_POS_LOOP                          ;#4D37: 18 AE

CHANGE_COPY_SUFFIX_ENTRY:
        ; Line had >=1 match — copy rest of source line tail through MEGA_LIST_BUF
        ld      hl,(MEGA_CHANGE_SRC_PTR)                       ;#4D39: 2A 1E EC
        ld      de,(MEGA_CHANGE_DST_PTR)                       ;#4D3C: ED 5B 20 EC
CHANGE_COPY_SUFFIX_LOOP:
        ; Per-byte body of suffix copy: read via SLOT_READ_HL, write to (de), test 0
        call    MEGA_SLOT_READ_HL                              ;#4D40: CD 16 FA
        ld      (de),a                                         ;#4D43: 12
        inc     hl                                             ;#4D44: 23
        inc     de                                             ;#4D45: 13
        or      a                                              ;#4D46: B7
        jr      nz,CHANGE_COPY_SUFFIX_LOOP                     ;#4D47: 20 F7
        ld      hl,(MEGA_SRC_LINE_PTR)                         ;#4D49: 2A 0B EC
        ld      de,MEGA_LIST_BUF                               ;#4D4C: 11 16 EE
        ld      bc,MEGA_LINE_NUMBER                            ;#4D4F: 01 0D EC
        call    MEGA_SLOT_READ_HL                              ;#4D52: CD 16 FA
        ld      (de),a                                         ;#4D55: 12
        ld      (bc),a                                         ;#4D56: 02
        inc     hl                                             ;#4D57: 23
        inc     de                                             ;#4D58: 13
        inc     bc                                             ;#4D59: 03
        call    MEGA_SLOT_READ_HL                              ;#4D5A: CD 16 FA
        ld      (de),a                                         ;#4D5D: 12
        ld      (bc),a                                         ;#4D5E: 02
        dec     de                                             ;#4D5F: 1B
        push    de                                             ;#4D60: D5
        inc     de                                             ;#4D61: 13
        inc     de                                             ;#4D62: 13
        ex      de,hl                                          ;#4D63: EB
        call    FIND_AND_MEASURE_LINE                          ;#4D64: CD 55 4E
        pop     de                                             ;#4D67: D1
        call    SEARCH_REPORT_MATCH                            ;#4D68: CD 50 49
        jp      CHANGE_NEXT_LINE                               ;#4D6B: C3 01 4D

CHANGE_NOT_FOUND:
        ; Jump target when CHANGE separator can't be located in input
        jp      SYNTAX_ERROR                                   ;#4D6E: C3 B9 41

CHANGE_DONE:
        ; Jump target — successful change completes; jp MEGA_PROMPT_TICK
        jp      MEGA_PROMPT_TICK                               ;#4D71: C3 19 41

MEGA_PCMD_DELETE:
        ; Prompt command "DELETE" — parse start,end then delete that line range
        call    SKIP_SPACES_RAW                                ;#4D74: CD 0E 5C
        or      a                                              ;#4D77: B7
        scf                                                    ;#4D78: 37
        jr      z,MEGA_PCMD_DELETE_ERR                         ;#4D79: 28 0F
        ld      a,2                                            ;#4D7B: 3E 02
        call    AUTO_PARSE_ARGS                                ;#4D7D: CD 05 50
        ld      hl,(MEGA_AUTO_LINE_INCREMENT)                  ;#4D80: 2A 16 EC
        ld      de,(MEGA_AUTO_LINE_NUMBER)                     ;#4D83: ED 5B 14 EC
        or      a                                              ;#4D87: B7
        sbc     hl,de                                          ;#4D88: ED 52
MEGA_PCMD_DELETE_ERR:
        ; jp c, SYNTAX_ERROR trampoline — 3 jr-callers (no arg / 2 LOCATE failures)
        jp      c,SYNTAX_ERROR                                 ;#4D8A: DA B9 41
        ld      (MEGA_LINE_NUMBER),de                          ;#4D8D: ED 53 0D EC
        call    LOCATE_LINE_BY_NUMBER                          ;#4D91: CD BF 4F
        jr      c,MEGA_PCMD_DELETE_ERR                         ;#4D94: 38 F4
        ld      hl,(MEGA_SRC_LINE_PTR)                         ;#4D96: 2A 0B EC
        ld      (MEGA_LINE_RANGE_END),hl                       ;#4D99: 22 22 EC
        ld      hl,(MEGA_AUTO_LINE_INCREMENT)                  ;#4D9C: 2A 16 EC
        ld      (MEGA_LINE_NUMBER),hl                          ;#4D9F: 22 0D EC
        call    LOCATE_LINE_BY_NUMBER                          ;#4DA2: CD BF 4F
        jr      c,MEGA_PCMD_DELETE_ERR                         ;#4DA5: 38 E3
        call    DELETE_LINE_RANGE                              ;#4DA7: CD 19 4F
        jp      MEGA_PROMPT_TICK                               ;#4DAA: C3 19 41

MEGA_PCMD_RENUM:
        ; Prompt command "RENUM" — renumber source lines starting from start,step
        ld      de,(MEGA_SRC_BUF_START)                        ;#4DAD: ED 5B 01 EC
        call    FIND_SOURCE_LINE_BY_NUMBER                     ;#4DB1: CD A7 4C
        jr      c,RENUM_DONE                                   ;#4DB4: 38 5E
        ld      a,3                                            ;#4DB6: 3E 03
        call    AUTO_PARSE_ARGS                                ;#4DB8: CD 05 50
RENUM_FIND_START:
        ; Locate the first source line ≥ start; clear MEGA_AUTO_FIRST_FLAG
        ld      hl,(MEGA_AUTO_LINE_NUMBER)                     ;#4DBB: 2A 14 EC
        ld      (MEGA_LINE_NUMBER),hl                          ;#4DBE: 22 0D EC
        call    LOCATE_LINE_BY_NUMBER                          ;#4DC1: CD BF 4F
        ld      hl,(MEGA_SRC_LINE_PTR)                         ;#4DC4: 2A 0B EC
        push    hl                                             ;#4DC7: E5
        ld      hl,(MEGA_AUTO_LINE_INCREMENT)                  ;#4DC8: 2A 16 EC
        ld      (MEGA_LINE_NUMBER),hl                          ;#4DCB: 22 0D EC
        call    LOCATE_LINE_BY_NUMBER                          ;#4DCE: CD BF 4F
        pop     hl                                             ;#4DD1: E1
        jr      c,RENUM_ERROR                                  ;#4DD2: 38 43
        ld      de,(MEGA_SRC_LINE_PTR)                         ;#4DD4: ED 5B 0B EC
        call    COMPARE_HL_DE                                  ;#4DD8: CD 98 50
        jr      c,RENUM_ERROR                                  ;#4DDB: 38 3A
        ld      hl,(MEGA_AUTO_LINE_NUMBER)                     ;#4DDD: 2A 14 EC
        ld      a,h                                            ;#4DE0: 7C
        or      l                                              ;#4DE1: B5
        jr      z,RENUM_ERROR                                  ;#4DE2: 28 33
        ld      bc,(MEGA_LIST_LINE_PTR)                        ;#4DE4: ED 4B 18 EC
RENUM_LOOP:
        ; Per-line body — write new line number via MEGA_SLOT_WRITE, advance, loop
        call    FIND_SOURCE_LINE_BY_NUMBER                     ;#4DE8: CD A7 4C
        jr      c,RENUM_FIRST_TOUCH                            ;#4DEB: 38 1A
        ld      a,(MEGA_AUTO_FIRST_FLAG)                       ;#4DED: 3A 13 EC
        or      a                                              ;#4DF0: B7
        ex      de,hl                                          ;#4DF1: EB
        jr      z,RENUM_NEXT_LINE                              ;#4DF2: 28 0A
        ld      a,e                                            ;#4DF4: 7B
        call    MEGA_SLOT_WRITE                                ;#4DF5: CD 10 FA
        inc     hl                                             ;#4DF8: 23
        ld      a,d                                            ;#4DF9: 7A
        call    MEGA_SLOT_WRITE                                ;#4DFA: CD 10 FA
        dec     hl                                             ;#4DFD: 2B
RENUM_NEXT_LINE:
        ; AUTO-flag-clear arm — skip the slot rewrite, just advance to next line
        call    NEXT_SOURCE_LINE                               ;#4DFE: CD FB 4F
        ex      de,hl                                          ;#4E01: EB
        call    AUTO_LINE_ADVANCE                              ;#4E02: CD 43 4E
        jr      RENUM_LOOP                                     ;#4E05: 18 E1

RENUM_FIRST_TOUCH:
        ; Sentinel-arming path: set MEGA_AUTO_FIRST_FLAG to FFh, restart at 4DBB
        ld      a,(MEGA_AUTO_FIRST_FLAG)                       ;#4E07: 3A 13 EC
        or      a                                              ;#4E0A: B7
        jr      nz,RENUM_DONE                                  ;#4E0B: 20 07
        ld      a,0FFh                                         ;#4E0D: 3E FF
        ld      (MEGA_AUTO_FIRST_FLAG),a                       ;#4E0F: 32 13 EC
        jr      RENUM_FIND_START                               ;#4E12: 18 A7

RENUM_DONE:
        ; jp MEGA_PROMPT_TICK — successful exit
        jp      MEGA_PROMPT_TICK                               ;#4E14: C3 19 41

RENUM_ERROR:
        ; jp SYNTAX_ERROR — error exit
        jp      SYNTAX_ERROR                                   ;#4E17: C3 B9 41

MEGA_PCMD_AUTO:
        ; Prompt command "AUTO" — enable AUTO mode (state bit 7) and parse start/step args
        set     7,(ix)                                         ;#4E1A: DD CB 00 FE
        xor     a                                              ;#4E1E: AF
        call    AUTO_PARSE_ARGS                                ;#4E1F: CD 05 50
        jp      PROMPT_TICK_PRESERVE_FLAGS                     ;#4E22: C3 2C 41

PROMPT_TICK_AUTO_LINE:
        ; Per-prompt AUTO printer: shows current line number padded with spaces
        ld      hl,(MEGA_AUTO_LINE_NUMBER)                     ;#4E25: 2A 14 EC
        ld      bc,(MEGA_AUTO_LINE_INCREMENT)                  ;#4E28: ED 4B 16 EC
        ld      a,(MEGA_AUTO_FIRST_FLAG)                       ;#4E2C: 3A 13 EC
        or      a                                              ;#4E2F: B7
        call    nz,AUTO_LINE_ADVANCE                           ;#4E30: C4 43 4E
        ld      (MEGA_AUTO_LINE_NUMBER),hl                     ;#4E33: 22 14 EC
        ld      a," "                                          ;#4E36: 3E 20
        call    PRINT_CHAR                                     ;#4E38: CD B6 42
        call    PRINT_DEC_HL                                   ;#4E3B: CD 89 4F
        ld      a," "                                          ;#4E3E: 3E 20
        jp      PRINT_CHAR                                     ;#4E40: C3 B6 42

AUTO_LINE_ADVANCE:
        ; Add EC16 (increment) to EC14 (current line); raise overflow if it wraps
        add     hl,bc                                          ;#4E43: 09
        ret     nc                                             ;#4E44: D0
        call    PRINT_OVERFLOW                                 ;#4E45: CD E7 41
        jp      MEGA_PROMPT_TICK                               ;#4E48: C3 19 41

DUMP_INIT_DISABLE_HKEYC:
        ; DUMP-prelude: store A as cursor pos, nop out HKEYC so SETKEY-hooks idle
        ld      (MEGA_EDITOR_CURSOR_POS),a                     ;#4E4B: 32 39 FA
        jp      INSTALL_HKEYC_NULL                             ;#4E4E: C3 E7 7F
        nop                                                    ;#4E51: 00
        nop                                                    ;#4E52: 00
        nop                                                    ;#4E53: 00
        nop                                                    ;#4E54: 00

FIND_AND_MEASURE_LINE:
        ; LOCATE_LINE_BY_NUMBER then walk the body to compute BC = byte length of the line
        call    LOCATE_LINE_BY_NUMBER                          ;#4E55: CD BF 4F
        jr      c,FIND_AND_MEASURE_NEW                         ;#4E58: 38 1F
        push    hl                                             ;#4E5A: E5
        ld      hl,(MEGA_SRC_LINE_PTR)                         ;#4E5B: 2A 0B EC
        ld      bc,2                                           ;#4E5E: 01 02 00
        inc     hl                                             ;#4E61: 23
FIND_AND_MEASURE_BODY:
        ; Per-byte length walk: inc HL+BC, read via SLOT, loop until 0 terminator
        inc     bc                                             ;#4E62: 03
        inc     hl                                             ;#4E63: 23
        call    MEGA_SLOT_READ_HL                              ;#4E64: CD 16 FA
        or      a                                              ;#4E67: B7
        jr      nz,FIND_AND_MEASURE_BODY                       ;#4E68: 20 F8
        pop     hl                                             ;#4E6A: E1
        push    hl                                             ;#4E6B: E5
        call    SKIP_SPACES_RAW                                ;#4E6C: CD 0E 5C
        pop     hl                                             ;#4E6F: E1
        or      a                                              ;#4E70: B7
        jr      nz,LINE_INSERT_NEW                             ;#4E71: 20 12
        call    DELETE_ONE_LINE                                ;#4E73: CD 13 4F
        jp      FIND_AND_MEASURE_DONE                          ;#4E76: C3 DF 4E

FIND_AND_MEASURE_NEW:
        ; No existing line found — check input; SKIP_SPACES, jump to DONE if blank
        push    hl                                             ;#4E79: E5
        call    SKIP_SPACES_RAW                                ;#4E7A: CD 0E 5C
        pop     hl                                             ;#4E7D: E1
        or      a                                              ;#4E7E: B7
        jp      z,FIND_AND_MEASURE_DONE                        ;#4E7F: CA DF 4E
        ld      bc,0                                           ;#4E82: 01 00 00
LINE_INSERT_NEW:
        ; New-line insert path — measure new body length BC, locate insertion point
        push    hl                                             ;#4E85: E5
        ld      de,3                                           ;#4E86: 11 03 00
        xor     a                                              ;#4E89: AF
LINE_INSERT_MEASURE:
        ; Per-byte body length: inc DE+HL, scan for 0 terminator at (hl)
        inc     de                                             ;#4E8A: 13
        inc     hl                                             ;#4E8B: 23
        cp      (hl)                                           ;#4E8C: BE
        jr      nz,LINE_INSERT_MEASURE                         ;#4E8D: 20 FB
        ex      de,hl                                          ;#4E8F: EB
        ld      (MEGA_CHANGE_DST_PTR),hl                       ;#4E90: 22 20 EC
        sbc     hl,bc                                          ;#4E93: ED 42
        ex      de,hl                                          ;#4E95: EB
        jr      c,LINE_INSERT_SHRINK                           ;#4E96: 38 48
        jr      z,LINE_INSERT_COMMIT                           ;#4E98: 28 26
        pop     bc                                             ;#4E9A: C1
        ld      hl,(MEGA_SRC_BUF_HEAD)                         ;#4E9B: 2A 03 EC
        add     hl,de                                          ;#4E9E: 19
        ex      de,hl                                          ;#4E9F: EB
        ld      hl,(MEGA_SRC_BUF_END)                          ;#4EA0: 2A 05 EC
        dec     hl                                             ;#4EA3: 2B
        or      a                                              ;#4EA4: B7
        sbc     hl,de                                          ;#4EA5: ED 52
        jr      c,LINE_INSERT_NO_ROOM                          ;#4EA7: 38 55
        push    bc                                             ;#4EA9: C5
        ld      hl,(MEGA_SRC_BUF_HEAD)                         ;#4EAA: 2A 03 EC
        ld      (MEGA_SRC_BUF_HEAD),de                         ;#4EAD: ED 53 03 EC
        push    hl                                             ;#4EB1: E5
        inc     hl                                             ;#4EB2: 23
        ld      bc,(MEGA_SRC_LINE_PTR)                         ;#4EB3: ED 4B 0B EC
        or      a                                              ;#4EB7: B7
        sbc     hl,bc                                          ;#4EB8: ED 42
        ld      b,h                                            ;#4EBA: 44
        ld      c,l                                            ;#4EBB: 4D
        pop     hl                                             ;#4EBC: E1
        call    nz,MEGA_SLOT_LDDR                              ;#4EBD: C4 29 FA
LINE_INSERT_COMMIT:
        ; Post-LDDR: write line-number word at MEGA_SRC_LINE_PTR, LDIR new body in
        pop     de                                             ;#4EC0: D1
        ld      hl,(MEGA_SRC_LINE_PTR)                         ;#4EC1: 2A 0B EC
        ld      bc,(MEGA_LINE_NUMBER)                          ;#4EC4: ED 4B 0D EC
        ld      a,c                                            ;#4EC8: 79
        call    MEGA_SLOT_WRITE                                ;#4EC9: CD 10 FA
        inc     hl                                             ;#4ECC: 23
        ld      a,b                                            ;#4ECD: 78
        call    MEGA_SLOT_WRITE                                ;#4ECE: CD 10 FA
        inc     hl                                             ;#4ED1: 23
        ex      de,hl                                          ;#4ED2: EB
        ld      bc,(MEGA_CHANGE_DST_PTR)                       ;#4ED3: ED 4B 20 EC
        dec     bc                                             ;#4ED7: 0B
        dec     bc                                             ;#4ED8: 0B
        call    MEGA_SLOT_LDIR                                 ;#4ED9: CD 22 FA
        call    CLEAR_PASS1_DONE_FLAG                          ;#4EDC: CD 4B 49
FIND_AND_MEASURE_DONE:
        ; Common exit `ret` — two jp callers from the delete-line and no-input arms
        ret                                                    ;#4EDF: C9

LINE_INSERT_SHRINK:
        ; New body smaller than old — LDIR-copy remainder of buffer over the gap
        push    de                                             ;#4EE0: D5
        ld      hl,(MEGA_SRC_LINE_PTR)                         ;#4EE1: 2A 0B EC
        call    NEXT_SOURCE_LINE                               ;#4EE4: CD FB 4F
        ex      de,hl                                          ;#4EE7: EB
        ld      hl,(MEGA_SRC_BUF_HEAD)                         ;#4EE8: 2A 03 EC
        inc     hl                                             ;#4EEB: 23
        or      a                                              ;#4EEC: B7
        sbc     hl,de                                          ;#4EED: ED 52
        ld      b,h                                            ;#4EEF: 44
        ld      c,l                                            ;#4EF0: 4D
        pop     hl                                             ;#4EF1: E1
        add     hl,de                                          ;#4EF2: 19
        ex      de,hl                                          ;#4EF3: EB
        call    nz,MEGA_SLOT_LDIR                              ;#4EF4: C4 22 FA
        dec     de                                             ;#4EF7: 1B
        ld      (MEGA_SRC_BUF_HEAD),de                         ;#4EF8: ED 53 03 EC
        jr      LINE_INSERT_COMMIT                             ;#4EFC: 18 C2

LINE_INSERT_NO_ROOM:
        ; Source-buffer would overflow — PRINT_OUT_OF_MEMORY and jp PROMPT_TICK
        call    PRINT_OUT_OF_MEMORY                            ;#4EFE: CD F7 41
        jp      MEGA_PROMPT_TICK                               ;#4F01: C3 19 41

SKIP_AND_PARSE_HEX_WORD:
        ; Combined SKIP_SPACES + jp PARSE_HEX_WORD shorthand (used by MEGA_PCMD_SCR)
        call    SKIP_SPACES                                    ;#4F04: CD F3 43
        jp      PARSE_HEX_WORD                                 ;#4F07: C3 BA 50
        rept    9
        nop
        endr

DELETE_ONE_LINE:
        ; Set MEGA_LINE_RANGE_END from MEGA_SRC_LINE_PTR, fall into DELETE_LINE_RANGE
        ld      hl,(MEGA_SRC_LINE_PTR)                         ;#4F13: 2A 0B EC
        ld      (MEGA_LINE_RANGE_END),hl                       ;#4F16: 22 22 EC
DELETE_LINE_RANGE:
        ; Remove lines [MEGA_LINE_NUMBER..EC22] from source buffer via SLOT_LDIR
        call    CLEAR_PASS1_DONE_FLAG                          ;#4F19: CD 4B 49
        ld      hl,(MEGA_SRC_LINE_PTR)                         ;#4F1C: 2A 0B EC
        call    NEXT_SOURCE_LINE                               ;#4F1F: CD FB 4F
        ex      de,hl                                          ;#4F22: EB
        ld      hl,(MEGA_SRC_BUF_HEAD)                         ;#4F23: 2A 03 EC
        inc     hl                                             ;#4F26: 23
        or      a                                              ;#4F27: B7
        sbc     hl,de                                          ;#4F28: ED 52
        jp      c,SYNTAX_ERROR                                 ;#4F2A: DA B9 41
        ld      b,h                                            ;#4F2D: 44
        ld      c,l                                            ;#4F2E: 4D
        ld      hl,(MEGA_LINE_RANGE_END)                       ;#4F2F: 2A 22 EC
        ex      de,hl                                          ;#4F32: EB
        jr      z,DELETE_LINE_RANGE_TRIM                       ;#4F33: 28 03
        call    MEGA_SLOT_LDIR                                 ;#4F35: CD 22 FA
DELETE_LINE_RANGE_TRIM:
        ; Decrement DE and store new MEGA_SRC_BUF_HEAD
        dec     de                                             ;#4F38: 1B
        ld      (MEGA_SRC_BUF_HEAD),de                         ;#4F39: ED 53 03 EC
        ret                                                    ;#4F3D: C9

PARSE_LINE_NUMBER:
        ; Parse 1-5 decimal digits from (DE), store in MEGA_LINE_NUMBER (Z=no digits)
        ex      de,hl                                          ;#4F3E: EB
        ld      hl,0                                           ;#4F3F: 21 00 00
        ld      b,h                                            ;#4F42: 44
        ld      c,h                                            ;#4F43: 4C
PARSE_LINE_NUMBER_LOOP:
        ; Per-digit body: read (DE), sub '0', range-check, multiply HL × 10, add digit
        ld      a,(de)                                         ;#4F44: 1A
        sub     "0"                                            ;#4F45: D6 30
        jr      c,PARSE_LINE_NUMBER_END                        ;#4F47: 38 19
        cp      0Ah                                            ;#4F49: FE 0A
        jr      nc,PARSE_LINE_NUMBER_END                       ;#4F4B: 30 15
        push    bc                                             ;#4F4D: C5
        ld      c,a                                            ;#4F4E: 4F
        push    de                                             ;#4F4F: D5
        ld      d,h                                            ;#4F50: 54
        ld      e,l                                            ;#4F51: 5D
        add     hl,hl                                          ;#4F52: 29
        add     hl,hl                                          ;#4F53: 29
        add     hl,de                                          ;#4F54: 19
        add     hl,hl                                          ;#4F55: 29
        add     hl,bc                                          ;#4F56: 09
        pop     de                                             ;#4F57: D1
        inc     de                                             ;#4F58: 13
        pop     bc                                             ;#4F59: C1
        ret     c                                              ;#4F5A: D8
        inc     c                                              ;#4F5B: 0C
        ld      a,5                                            ;#4F5C: 3E 05
        cp      c                                              ;#4F5E: B9
        jr      nc,PARSE_LINE_NUMBER_LOOP                      ;#4F5F: 30 E3
        ret                                                    ;#4F61: C9

PARSE_LINE_NUMBER_END:
        ; Non-digit terminator path of PARSE_LINE_NUMBER — saves HL to MEGA_LINE_NUMBER
        ld      (MEGA_LINE_NUMBER),hl                          ;#4F62: 22 0D EC
        ex      de,hl                                          ;#4F65: EB
        or      a                                              ;#4F66: B7
        inc     c                                              ;#4F67: 0C
        dec     c                                              ;#4F68: 0D
        ret                                                    ;#4F69: C9

PUSH_DIGITS_HL:
        ; Repeatedly divide HL by 10, push each decimal digit onto stack (CF=0 sentinel)
        pop     de                                             ;#4F6A: D1
        or      a                                              ;#4F6B: B7
        push    af                                             ;#4F6C: F5
PUSH_DIGITS_DIV_LOOP:
        ; Per-digit body — 16-bit divide HL/10, push remainder, fall back if HL≠0
        push    bc                                             ;#4F6D: C5
        ld      bc,100Ah                                       ;#4F6E: 01 0A 10
        xor     a                                              ;#4F71: AF
PUSH_DIGITS_BIT_TICK:
        ; Per-bit body — restoring-divide shift one bit of HL/10
        add     hl,hl                                          ;#4F72: 29
        rla                                                    ;#4F73: 17
        cp      c                                              ;#4F74: B9
        jr      c,PUSH_DIGITS_BIT_LOOP                         ;#4F75: 38 02
        sub     c                                              ;#4F77: 91
        inc     l                                              ;#4F78: 2C
PUSH_DIGITS_BIT_LOOP:
        ; Inner divide tail — djnz over 16 bits (B=10h); C=10 is the divisor
        djnz    PUSH_DIGITS_BIT_TICK                           ;#4F79: 10 F7
        pop     bc                                             ;#4F7B: C1
        scf                                                    ;#4F7C: 37
        push    af                                             ;#4F7D: F5
        dec     c                                              ;#4F7E: 0D
        ld      a,h                                            ;#4F7F: 7C
        or      l                                              ;#4F80: B5
        jr      nz,PUSH_DIGITS_DIV_LOOP                        ;#4F81: 20 EA
        push    de                                             ;#4F83: D5
        ret                                                    ;#4F84: C9

PRINT_DEC_HL_PAD4:
        ; Print HL as decimal preceded by 4 spaces (used by paging banner)
        ld      c,4                                            ;#4F85: 0E 04
        jr      PRINT_DEC_HL_ENTRY                             ;#4F87: 18 02

PRINT_DEC_HL:
        ; Print HL as decimal with no leading padding
        ld      c,0                                            ;#4F89: 0E 00
PRINT_DEC_HL_ENTRY:
        ; Shared entry: PUSH_DIGITS_HL then pad+emit
        call    PUSH_DIGITS_HL                                 ;#4F8B: CD 6A 4F
        jr      PRINT_DEC_PAD_LOOP                             ;#4F8E: 18 05

PRINT_DEC_PAD_SPC:
        ; Pad-emit arm — print one space and re-test C (jp p loop)
        ld      a," "                                          ;#4F90: 3E 20
        call    PRINT_CHAR_DUAL                                ;#4F92: CD C4 42
PRINT_DEC_PAD_LOOP:
        ; Pad-with-spaces loop of PRINT_DEC_HL — print ' ' until C wraps negative
        dec     c                                              ;#4F95: 0D
        jp      p,PRINT_DEC_PAD_SPC                            ;#4F96: F2 90 4F
PRINT_DEC_DIGIT_LOOP:
        ; Pop-and-emit digit loop — pop AF, CF=0 = no more, else add '0' and print
        pop     af                                             ;#4F99: F1
        ret     nc                                             ;#4F9A: D0
        add     a,"0"                                          ;#4F9B: C6 30
        call    PRINT_CHAR_DUAL                                ;#4F9D: CD C4 42
        jr      PRINT_DEC_DIGIT_LOOP                           ;#4FA0: 18 F7

STORE_DEC_HL_TO_LINE:
        ; Write HL as decimal at MEGA_DISASM_LINE+1 (1-space prefix); HL out = next free
        ld      c,0                                            ;#4FA2: 0E 00
        call    PUSH_DIGITS_HL                                 ;#4FA4: CD 6A 4F
        ld      hl,MEGA_DISASM_LINE                            ;#4FA7: 21 C3 EC
        ld      (hl)," "                                       ;#4FAA: 36 20
        inc     hl                                             ;#4FAC: 23
        jr      STORE_DEC_PAD_LOOP                             ;#4FAD: 18 04

STORE_DEC_PAD_SPC:
        ; Pad-store arm — write one space at (hl), inc hl, re-test C
        ld      a," "                                          ;#4FAF: 3E 20
        ld      (hl),a                                         ;#4FB1: 77
        inc     hl                                             ;#4FB2: 23
STORE_DEC_PAD_LOOP:
        ; Inner loop of STORE_DEC_HL_TO_LINE: pad with spaces, then pop+emit digit at HL
        dec     c                                              ;#4FB3: 0D
        jp      p,STORE_DEC_PAD_SPC                            ;#4FB4: F2 AF 4F
STORE_DEC_DIGIT_LOOP:
        ; Pop-and-store digit loop of STORE_DEC_HL_TO_LINE
        pop     af                                             ;#4FB7: F1
        ret     nc                                             ;#4FB8: D0
        add     a,"0"                                          ;#4FB9: C6 30
        ld      (hl),a                                         ;#4FBB: 77
        inc     hl                                             ;#4FBC: 23
        jr      STORE_DEC_DIGIT_LOOP                           ;#4FBD: 18 F8

LOCATE_LINE_BY_NUMBER:
        ; Walk source buffer to find line whose number ≥ MEGA_LINE_NUMBER; addr → EC0B
        push    hl                                             ;#4FBF: E5
        ld      hl,(MEGA_SRC_BUF_START)                        ;#4FC0: 2A 01 EC
        bit     3,(ix)                                         ;#4FC3: DD CB 00 5E
        jr      z,LOCATE_LINE_NEXT                             ;#4FC7: 28 03
        ld      hl,(MEGA_SRC_LINE_PTR)                         ;#4FC9: 2A 0B EC
LOCATE_LINE_NEXT:
        ; Per-iteration body of LOCATE_LINE_BY_NUMBER — read line-number word, compare
        ex      de,hl                                          ;#4FCC: EB
        ld      hl,(MEGA_SRC_BUF_HEAD)                         ;#4FCD: 2A 03 EC
        or      a                                              ;#4FD0: B7
        sbc     hl,de                                          ;#4FD1: ED 52
        ex      de,hl                                          ;#4FD3: EB
        jr      c,LOCATE_LINE_FOUND_STORE                      ;#4FD4: 38 20
        call    MEGA_SLOT_READ_HL                              ;#4FD6: CD 16 FA
        ld      e,a                                            ;#4FD9: 5F
        inc     hl                                             ;#4FDA: 23
        call    MEGA_SLOT_READ_HL                              ;#4FDB: CD 16 FA
        ld      d,a                                            ;#4FDE: 57
        push    hl                                             ;#4FDF: E5
        ld      hl,(MEGA_LINE_NUMBER)                          ;#4FE0: 2A 0D EC
        or      a                                              ;#4FE3: B7
        sbc     hl,de                                          ;#4FE4: ED 52
        pop     hl                                             ;#4FE6: E1
        jr      c,LOCATE_LINE_FOUND                            ;#4FE7: 38 0C
        jr      z,LOCATE_LINE_FOUND                            ;#4FE9: 28 0A
        inc     hl                                             ;#4FEB: 23
LOCATE_LINE_SKIP_BODY:
        ; No match: walk past the line body bytes until null terminator, then loop back
        call    MEGA_SLOT_READ_HL                              ;#4FEC: CD 16 FA
        or      a                                              ;#4FEF: B7
        inc     hl                                             ;#4FF0: 23
        jr      nz,LOCATE_LINE_SKIP_BODY                       ;#4FF1: 20 F9
        jr      LOCATE_LINE_NEXT                               ;#4FF3: 18 D7

LOCATE_LINE_FOUND:
        ; Match: rewind one byte, store hit address into MEGA_SRC_LINE_PTR, ret
        dec     hl                                             ;#4FF5: 2B
LOCATE_LINE_FOUND_STORE:
        ; Common store arm — `ld (MEGA_SRC_LINE_PTR),hl` + pop + ret
        ld      (MEGA_SRC_LINE_PTR),hl                         ;#4FF6: 22 0B EC
        pop     hl                                             ;#4FF9: E1
        ret                                                    ;#4FFA: C9

NEXT_SOURCE_LINE:
        ; Advance HL to the start of the next source line in the buffer
        inc     hl                                             ;#4FFB: 23
        inc     hl                                             ;#4FFC: 23
NEXT_SOURCE_LINE_BODY:
        ; Per-byte advance — read via SLOT_READ_HL, inc HL, loop until 0 terminator
        call    MEGA_SLOT_READ_HL                              ;#4FFD: CD 16 FA
        or      a                                              ;#5000: B7
        inc     hl                                             ;#5001: 23
        jr      nz,NEXT_SOURCE_LINE_BODY                       ;#5002: 20 F9
        ret                                                    ;#5004: C9

AUTO_PARSE_ARGS:
        ; Parse the `start,increment` arguments of MEGA_PCMD_AUTO into EC14/EC16
        ld      (MEGA_AUTO_FIRST_ARG),a                        ;#5005: 32 24 EC
        ex      de,hl                                          ;#5008: EB
        ld      hl,0Ah                                         ;#5009: 21 0A 00
        ld      (MEGA_AUTO_LINE_NUMBER),hl                     ;#500C: 22 14 EC
        ld      (MEGA_AUTO_LINE_INCREMENT),hl                  ;#500F: 22 16 EC
        ld      (MEGA_LIST_LINE_PTR),hl                        ;#5012: 22 18 EC
        cp      3                                              ;#5015: FE 03
        jr      nz,AUTO_PARSE_FIRST                            ;#5017: 20 11
        ld      hl,(MEGA_SRC_BUF_START)                        ;#5019: 2A 01 EC
        call    MEGA_SLOT_READ_HL                              ;#501C: CD 16 FA
        inc     hl                                             ;#501F: 23
        push    af                                             ;#5020: F5
        call    MEGA_SLOT_READ_HL                              ;#5021: CD 16 FA
        ld      h,a                                            ;#5024: 67
        pop     af                                             ;#5025: F1
        ld      l,a                                            ;#5026: 6F
        ld      (MEGA_AUTO_LINE_INCREMENT),hl                  ;#5027: 22 16 EC
AUTO_PARSE_FIRST:
        ; After optional first-arg read — skip whitespace; if EOL go to DONE
        ex      de,hl                                          ;#502A: EB
        call    SKIP_SPACES_RAW                                ;#502B: CD 0E 5C
        or      a                                              ;#502E: B7
        jr      z,AUTO_PARSE_DONE                              ;#502F: 28 34
        call    PARSE_REQUIRED_LINE_NUMBER                     ;#5031: CD 79 50
        ld      (MEGA_AUTO_LINE_NUMBER),de                     ;#5034: ED 53 14 EC
        ld      a,(MEGA_AUTO_FIRST_ARG)                        ;#5038: 3A 24 EC
        cp      2                                              ;#503B: FE 02
        jr      nz,AUTO_PARSE_SECOND                           ;#503D: 20 04
        ld      (MEGA_AUTO_LINE_INCREMENT),de                  ;#503F: ED 53 16 EC
AUTO_PARSE_SECOND:
        ; After first start-number — parse optional second arg (increment)
        ld      a,(hl)                                         ;#5043: 7E
        inc     hl                                             ;#5044: 23
        or      a                                              ;#5045: B7
        jr      z,AUTO_PARSE_DONE                              ;#5046: 28 1D
        call    PARSE_REQUIRED_LINE_NUMBER                     ;#5048: CD 79 50
        ld      (MEGA_AUTO_LINE_INCREMENT),de                  ;#504B: ED 53 16 EC
        ld      a,(MEGA_AUTO_FIRST_ARG)                        ;#504F: 3A 24 EC
        cp      0                                              ;#5052: FE 00
        jr      z,AUTO_PARSE_TAIL                              ;#5054: 28 0C
        ld      a,(hl)                                         ;#5056: 7E
        inc     hl                                             ;#5057: 23
        or      a                                              ;#5058: B7
        jr      z,AUTO_PARSE_DONE                              ;#5059: 28 0A
        call    PARSE_REQUIRED_LINE_NUMBER                     ;#505B: CD 79 50
        ld      (MEGA_LIST_LINE_PTR),de                        ;#505E: ED 53 18 EC
AUTO_PARSE_TAIL:
        ; After all args — PROMPT_TICK_TAIL_CHECK (rejects trailing junk)
        call    PROMPT_TICK_TAIL_CHECK                         ;#5062: CD B5 41
AUTO_PARSE_DONE:
        ; Args parsed (or input exhausted): clear MEGA_AUTO_FIRST_FLAG and enter AUTO mode
        xor     a                                              ;#5065: AF
        ld      (MEGA_AUTO_FIRST_FLAG),a                       ;#5066: 32 13 EC
        ld      hl,(MEGA_AUTO_LINE_INCREMENT)                  ;#5069: 2A 16 EC
        ld      a,h                                            ;#506C: 7C
        or      l                                              ;#506D: B5
        jr      z,AUTO_PARSE_NO_INCR                           ;#506E: 28 06
        ld      hl,(MEGA_LIST_LINE_PTR)                        ;#5070: 2A 18 EC
        ld      a,h                                            ;#5073: 7C
        or      l                                              ;#5074: B5
        ret     nz                                             ;#5075: C0
AUTO_PARSE_NO_INCR:
        ; Both increment and line-ptr ended up zero — jp SYNTAX_ERROR
        jp      SYNTAX_ERROR                                   ;#5076: C3 B9 41

PARSE_REQUIRED_LINE_NUMBER:
        ; Skip spaces + PARSE_LINE_NUMBER; raise SYNTAX_ERROR on parse fail or no digits
        call    SKIP_SPACES_RAW                                ;#5079: CD 0E 5C
        call    PARSE_LINE_NUMBER                              ;#507C: CD 3E 4F
        ld      de,(MEGA_LINE_NUMBER)                          ;#507F: ED 5B 0D EC
        jp      c,SYNTAX_ERROR                                 ;#5083: DA B9 41
        jp      z,SYNTAX_ERROR                                 ;#5086: CA B9 41
        ret                                                    ;#5089: C9

PRINT_INLINE_STRING:
        ; Print the bit7-mask string that follows the call; terminator = bit-7-set byte
        ex      (sp),hl                                        ;#508A: E3
        ld      a,(hl)                                         ;#508B: 7E
        and     7Fh                                            ;#508C: E6 7F
        call    PRINT_CHAR                                     ;#508E: CD B6 42
        bit     7,(hl)                                         ;#5091: CB 7E
        inc     hl                                             ;#5093: 23
        ex      (sp),hl                                        ;#5094: E3
        jr      z,PRINT_INLINE_STRING                          ;#5095: 28 F3
        ret                                                    ;#5097: C9

COMPARE_HL_DE:
        ; Return flags from HL−DE with HL preserved: Z=equal, C=HL<DE
        push    hl                                             ;#5098: E5
        or      a                                              ;#5099: B7
        sbc     hl,de                                          ;#509A: ED 52
        pop     hl                                             ;#509C: E1
        ret                                                    ;#509D: C9

PRINT_HEX_HL:
        ; Print HL as four hex digits (high byte first)
        ld      a,h                                            ;#509E: 7C
        call    PRINT_HEX_A                                    ;#509F: CD A3 50
        ld      a,l                                            ;#50A2: 7D
PRINT_HEX_A:
        ; Print A as two hex digits
        push    af                                             ;#50A3: F5
        rrca                                                   ;#50A4: 0F
        rrca                                                   ;#50A5: 0F
        rrca                                                   ;#50A6: 0F
        rrca                                                   ;#50A7: 0F
        call    PRINT_NIBBLE_HEX                               ;#50A8: CD AC 50
        pop     af                                             ;#50AB: F1
PRINT_NIBBLE_HEX:
        ; Print low nibble of A as one hex digit
        call    NIBBLE_TO_ASCII                                ;#50AC: CD B2 50
        jp      PRINT_CHAR                                     ;#50AF: C3 B6 42

NIBBLE_TO_ASCII:
        ; Map A & 0Fh → '0'..'9' or 'A'..'F' (via sbc/daa idiom)
        and     0Fh                                            ;#50B2: E6 0F
        cp      0Ah                                            ;#50B4: FE 0A
        sbc     a,69h                                          ;#50B6: DE 69
        daa                                                    ;#50B8: 27
        ret                                                    ;#50B9: C9

PARSE_HEX_WORD:
        ; Parse up to 4 hex chars from (HL) into DE; NC = valid, C = no digits
        ld      bc,3                                           ;#50BA: 01 03 00
        ld      a,(hl)                                         ;#50BD: 7E
        call    PARSE_HEX_CHAR                                 ;#50BE: CD E7 50
        ret     c                                              ;#50C1: D8
        ld      d,b                                            ;#50C2: 50
        ld      e,a                                            ;#50C3: 5F
PARSE_HEX_WORD_LOOP:
        ; Per-digit body — advance HL, parse next hex char into DE, retry 3× total
        inc     hl                                             ;#50C4: 23
        ld      a,(hl)                                         ;#50C5: 7E
        call    PARSE_HEX_DIGIT_INTO_DE                        ;#50C6: CD D4 50
        ret     nc                                             ;#50C9: D0
        dec     c                                              ;#50CA: 0D
        jr      nz,PARSE_HEX_WORD_LOOP                         ;#50CB: 20 F7
        inc     hl                                             ;#50CD: 23
        ld      a,(hl)                                         ;#50CE: 7E
        call    PARSE_HEX_CHAR                                 ;#50CF: CD E7 50
        ccf                                                    ;#50D2: 3F
        ret                                                    ;#50D3: C9

PARSE_HEX_DIGIT_INTO_DE:
        ; Per-digit body of PARSE_HEX_WORD — shifts DE left 4 and ORs in the nibble
        call    PARSE_HEX_CHAR                                 ;#50D4: CD E7 50
        ccf                                                    ;#50D7: 3F
        ret     nc                                             ;#50D8: D0
        ex      de,hl                                          ;#50D9: EB
        add     hl,hl                                          ;#50DA: 29
        add     hl,hl                                          ;#50DB: 29
        add     hl,hl                                          ;#50DC: 29
        add     hl,hl                                          ;#50DD: 29
        push    bc                                             ;#50DE: C5
        ld      b,0                                            ;#50DF: 06 00
        ld      c,a                                            ;#50E1: 4F
        add     hl,bc                                          ;#50E2: 09
        ex      de,hl                                          ;#50E3: EB
        pop     bc                                             ;#50E4: C1
        scf                                                    ;#50E5: 37
        ret                                                    ;#50E6: C9

PARSE_HEX_CHAR:
        ; Convert A from '0'..'9','A'..'F','a'..'f' to 0..15; NC = valid
        call    PARSE_DIGIT_CHAR                               ;#50E7: CD F8 50
        ret     nc                                             ;#50EA: D0
        call    TO_UPPER                                       ;#50EB: CD 22 47
        cp      "A"                                            ;#50EE: FE 41
        ret     c                                              ;#50F0: D8
        cp      "F"+1                                          ;#50F1: FE 47
        ccf                                                    ;#50F3: 3F
        ret     c                                              ;#50F4: D8
        sub     "7"                                            ;#50F5: D6 37
        ret                                                    ;#50F7: C9

PARSE_DIGIT_CHAR:
        ; Convert A from '0'..'9' to 0..9; NC = valid
        cp      "0"                                            ;#50F8: FE 30
        ret     c                                              ;#50FA: D8
        cp      "9"+1                                          ;#50FB: FE 3A
        ccf                                                    ;#50FD: 3F
        ret     c                                              ;#50FE: D8
        sub     "0"                                            ;#50FF: D6 30
        ret                                                    ;#5101: C9

MEGA_PCMD_A:
MEGA_ASSEMBLE:
        ; Two-pass assembler driver (alias of MEGA_PCMD_A): runs PASS1 then PASS2
        ld      (MEGA_SAVED_SP_ASM),sp                         ;#5102: ED 73 66 EC
        xor     a                                              ;#5106: AF
        ld      b,a                                            ;#5107: 47
        ld      c,a                                            ;#5108: 4F
        ld      (MEGA_ASM_RELOC_OFFSET),bc                     ;#5109: ED 43 F8 F9
        ld      (MEGA_LIST_FROM_OFFSET),a                      ;#510D: 32 6B EC
        ld      e,a                                            ;#5110: 5F
        call    SKIP_SPACES_RAW                                ;#5111: CD 0E 5C
ASM_PARSE_OPT_CHARS:
        ; Loop over leading option chars, looking each up in ASM_OPT_CHAR_TABLE
        ld      a,(hl)                                         ;#5114: 7E
        inc     hl                                             ;#5115: 23
        push    hl                                             ;#5116: E5
        ld      hl,ASM_OPT_CHAR_TABLE                          ;#5117: 21 55 51
        ld      bc,8                                           ;#511A: 01 08 00
        cpir                                                   ;#511D: ED B1
        pop     hl                                             ;#511F: E1
        jr      nz,ASM_OPT_CHECK_N                             ;#5120: 20 0B
        inc     c                                              ;#5122: 0C
        ld      a,1                                            ;#5123: 3E 01
ASM_OPT_BIT_SHIFT:
        ; Turn the CPIR-derived index C into a bitmask via 1>>C rotates
        rrca                                                   ;#5125: 0F
        dec     c                                              ;#5126: 0D
        jr      nz,ASM_OPT_BIT_SHIFT                           ;#5127: 20 FC
        or      e                                              ;#5129: B3
        ld      e,a                                            ;#512A: 5F
        jr      ASM_PARSE_OPT_CHARS                            ;#512B: 18 E7

ASM_OPT_CHECK_N:
        ; Not in option table — test for "N" (no-listing) directly
        cp      "N"                                            ;#512D: FE 4E
        jr      nz,ASM_OPT_CHECK_SLASH                         ;#512F: 20 05
        ld      (MEGA_LIST_FROM_OFFSET),a                      ;#5131: 32 6B EC
        jr      ASM_PARSE_OPT_CHARS                            ;#5134: 18 DE

ASM_OPT_CHECK_SLASH:
        ; Not "N" — test for "/" (reloc-offset prefix) or EOL
        or      a                                              ;#5136: B7
        jr      z,ASM_OPT_DONE                                 ;#5137: 28 24
        cp      "/"                                            ;#5139: FE 2F
        jr      nz,ASM_OPT_BAD                                 ;#513B: 20 0F
        push    de                                             ;#513D: D5
        call    PARSE_HEX_WORD                                 ;#513E: CD BA 50
        ld      (MEGA_ASM_RELOC_OFFSET),de                     ;#5141: ED 53 F8 F9
        pop     de                                             ;#5145: D1
        jr      c,ASM_OPT_BAD                                  ;#5146: 38 04
        ld      a,(hl)                                         ;#5148: 7E
        or      a                                              ;#5149: B7
        jr      z,ASM_OPT_DONE                                 ;#514A: 28 11
ASM_OPT_BAD:
        ; Bad option / parse-failed path: print "?\a\r" and jp MEGA_PROMPT_TICK
        call    PRINT_INLINE_STRING                            ;#514C: CD 8A 50
        db      "?", 7, 8Dh                                    ;#514F: 3F 07 8D
        jp      MEGA_PROMPT_TICK                               ;#5152: C3 19 41

ASM_OPT_CHAR_TABLE:
        ; 8-byte option-flag character table searched by `A` to set state-flag bits
        ; Format: FORMAT_RAW_STRING
        ; - For embedded text that isn't 0-terminated or bit-7-terminated.
        db      "UPOIRHSD"                                     ;#5155: 55 50 4F 49 52 48 53 44

ASM_OPT_DONE:
        ; Options parsed: flip bit 0 of state flags, init PASS1 cursors, start assembly
        ld      a,e                                            ;#515D: 7B
        xor     1                                              ;#515E: EE 01
        ld      (MEGA_STATE_FLAGS),a                           ;#5160: 32 F5 F9
        ld      hl,(MEGA_SRC_BUF_START)                        ;#5163: 2A 01 EC
        ld      (MEGA_ASM_PASS2_START),hl                      ;#5166: 22 4D EC
        ld      hl,(MEGA_SRC_BUF_HEAD)                         ;#5169: 2A 03 EC
        inc     hl                                             ;#516C: 23
        ld      (MEGA_SYM_TABLE_BASE),hl                       ;#516D: 22 49 EC
        ld      a,(MEGA_PASS1_DONE_FLAG)                       ;#5170: 3A 26 EC
        or      a                                              ;#5173: B7
        jr      nz,ASSEMBLE_PASS2_ENTRY                        ;#5174: 20 49
        call    PRINT_PASS_1_BANNER                            ;#5176: CD 0B 42
        nop                                                    ;#5179: 00
        nop                                                    ;#517A: 00
        nop                                                    ;#517B: 00
        nop                                                    ;#517C: 00
        nop                                                    ;#517D: 00
        nop                                                    ;#517E: 00
        nop                                                    ;#517F: 00
        ld      hl,1                                           ;#5180: 21 01 00
        ld      (DISASM_PAGE_NUMBER),hl                        ;#5183: 22 5A EC
        xor     a                                              ;#5186: AF
        ld      (DISASM_LINES_LEFT),a                          ;#5187: 32 59 EC
        call    ASSEMBLE_PASS_PREP                             ;#518A: CD 31 52
        ld      hl,(MEGA_SYM_TABLE_BASE)                       ;#518D: 2A 49 EC
        xor     a                                              ;#5190: AF
        call    MEGA_SLOT_WRITE                                ;#5191: CD 10 FA
        ld      ix,MEGA_STATE_FLAGS                            ;#5194: DD 21 F5 F9
        xor     a                                              ;#5198: AF
        ld      (MEGA_ASM_PASS_FLAG),a                         ;#5199: 32 F6 F9
ASSEMBLE_PASS1_LOOP:
        ; Pass 1 main loop — parse one source line per iteration
        call    CHECK_USER_INTERRUPT                           ;#519C: CD 9D 42
        jr      c,ASSEMBLE_ABORT                               ;#519F: 38 14
        call    ASM_FETCH_NEXT_LINE                            ;#51A1: CD 45 52
        jr      c,ASSEMBLE_PASS1_DONE                          ;#51A4: 38 08
        call    ASSEMBLE_LINE_INIT                             ;#51A6: CD 98 52
        jr      nc,ASSEMBLE_PASS1_LOOP                         ;#51A9: 30 F1
        jp      m,ASSEMBLE_ABORT                               ;#51AB: FA B5 51
ASSEMBLE_PASS1_DONE:
        ; Set EC26 to "pass 1 complete" then continue into pass 2
        ld      a,0FFh                                         ;#51AE: 3E FF
        ld      (MEGA_PASS1_DONE_FLAG),a                       ;#51B0: 32 26 EC
        jr      ASSEMBLE_PASS2_ENTRY                           ;#51B3: 18 0A

ASSEMBLE_ABORT:
        ; Cleanup-and-restart: print CR, restore SP from EC66h, jp to prompt
        call    PRINT_CR                                       ;#51B5: CD B4 42
        ld      sp,(MEGA_SAVED_SP_ASM)                         ;#51B8: ED 7B 66 EC
        jp      MEGA_PROMPT_TICK                               ;#51BC: C3 19 41

ASSEMBLE_PASS2_ENTRY:
        ; Pass 2 setup — restore SP, init state, print PASSO-2 banner
        ld      sp,(MEGA_SAVED_SP_ASM)                         ;#51BF: ED 7B 66 EC
        ld      ix,MEGA_STATE_FLAGS                            ;#51C3: DD 21 F5 F9
        call    ASM_CLEAR_SYMBOL_REFS                          ;#51C7: CD EC 54
        call    PRINT_PASS_2_BANNER                            ;#51CA: CD 18 42
        rept    8
        nop
        endr
        call    ASSEMBLE_PROGRESS_HOOK                         ;#51D5: CD E9 53
        call    ASSEMBLE_PASS_PREP                             ;#51D8: CD 31 52
        xor     a                                              ;#51DB: AF
        ld      (MEGA_ASM_PASS1_FLAG_LO),a                     ;#51DC: 32 6C EC
        set     0,(ix+1)                                       ;#51DF: DD CB 01 C6

ASSEMBLE_PASS2_LOOP:
        ; Pass 2 main loop — emit bytes for each parsed line
        call    CHECK_USER_INTERRUPT                           ;#51E3: CD 9D 42
        jr      c,ASSEMBLE_PASS2_ERROR                         ;#51E6: 38 44
        call    ASM_FETCH_NEXT_LINE                            ;#51E8: CD 45 52
        jr      c,ASSEMBLE_PASS2_DONE                          ;#51EB: 38 0A
        call    ASSEMBLE_LINE_INIT                             ;#51ED: CD 98 52
        jr      nc,ASSEMBLE_PASS2_LOOP                         ;#51F0: 30 F1
        jp      m,ASSEMBLE_PASS2_ERROR                         ;#51F2: FA 2C 52
        jr      ASSEMBLE_FINALIZE                              ;#51F5: 18 0E

ASSEMBLE_PASS2_DONE:
        ; Print "Fim do PASSO-2"; fall into ASSEMBLE_FINALIZE
        call    PRINT_PASS_2_DONE                              ;#51F7: CD 25 42
        rept    11
        nop
        endr

ASSEMBLE_FINALIZE:
        ; Post-pass cleanup; emit deferred labels via 53EAh; jump to ASSEMBLE_ABORT
        call    TAPE_WRITE_EOF                                 ;#5205: CD F1 55
        bit     7,(ix)                                         ;#5208: DD CB 00 7E
        jr      z,ASSEMBLE_FIN_BIT6                            ;#520C: 28 09
        call    ASM_PRINT_SYMBOLS                              ;#520E: CD EA 53
        jr      c,ASSEMBLE_FINALIZE_EXIT                       ;#5211: 38 16
        res     7,(ix)                                         ;#5213: DD CB 00 BE
ASSEMBLE_FIN_BIT6:
        ; Test bit 6 of state flags (print-deferred-symbols-2 enable)
        bit     6,(ix)                                         ;#5217: DD CB 00 76
        jr      z,ASSEMBLE_FIN_FORCED                          ;#521B: 28 09
        call    ASM_PRINT_SYMBOLS                              ;#521D: CD EA 53
        jr      c,ASSEMBLE_FINALIZE_EXIT                       ;#5220: 38 07
        res     6,(ix)                                         ;#5222: DD CB 00 B6
ASSEMBLE_FIN_FORCED:
        ; Always emit one final ASM_PRINT_SYMBOLS pass (no flag gating)
        call    ASM_PRINT_SYMBOLS                              ;#5226: CD EA 53
ASSEMBLE_FINALIZE_EXIT:
        ; Tail `jp ASSEMBLE_ABORT` — three callers (2 PRINT_SYMBOLS errors + pass2 retry)
        jp      ASSEMBLE_ABORT                                 ;#5229: C3 B5 51

ASSEMBLE_PASS2_ERROR:
        ; Pass 2 parse-error tail: call 55F1, jump to ASSEMBLE_ABORT via 5229
        call    TAPE_WRITE_EOF                                 ;#522C: CD F1 55
        jr      ASSEMBLE_FINALIZE_EXIT                         ;#522F: 18 F8

ASSEMBLE_PASS_PREP:
        ; Common init run at start of both passes (clear counters etc.)
        ld      hl,0                                           ;#5231: 21 00 00
        ld      (MEGA_DISASM_CURSOR),hl                        ;#5234: 22 5E EC
        ld      (MEGA_ASM_CURRENT_LINE),hl                     ;#5237: 22 62 EC
        ld      hl,(MEGA_ASM_PASS2_START)                      ;#523A: 2A 4D EC
        ld      (MEGA_ASM_PASS2_CURSOR),hl                     ;#523D: 22 4F EC
        xor     a                                              ;#5240: AF
        ld      (MEGA_TAPE_REC_COUNT),a                        ;#5241: 32 79 EC
        ret                                                    ;#5244: C9

ASM_FETCH_NEXT_LINE:
        ; Locate next source line, read line-number (EC62/63) and body bytes into ED14
        ld      de,(MEGA_ASM_PASS2_CURSOR)                     ;#5245: ED 5B 4F EC
        call    FIND_SOURCE_LINE_BY_NUMBER                     ;#5249: CD A7 4C
        ret     c                                              ;#524C: D8
        call    MEGA_SLOT_READ_DE                              ;#524D: CD 1C FA
        inc     de                                             ;#5250: 13
        ld      (MEGA_ASM_CURRENT_LINE),a                      ;#5251: 32 62 EC
        call    MEGA_SLOT_READ_DE                              ;#5254: CD 1C FA
        inc     de                                             ;#5257: 13
        ld      (MEGA_ASM_CURRENT_LINE_HI),a                   ;#5258: 32 63 EC
        ld      hl,MEGA_ASM_LINE_BUF                           ;#525B: 21 14 ED
        ld      b,0FFh                                         ;#525E: 06 FF
        ld      c,0                                            ;#5260: 0E 00
ASM_FETCH_LINE_BYTE:
        ; Per-byte read loop body: MEGA_SLOT_READ_DE, advance DE, store/skip based on byte
        call    MEGA_SLOT_READ_DE                              ;#5262: CD 1C FA
        inc     de                                             ;#5265: 13
        or      a                                              ;#5266: B7
        jr      z,ASM_FETCH_LINE_END                           ;#5267: 28 14
        cp      9                                              ;#5269: FE 09
        jr      z,ASM_FETCH_LINE_TAB                           ;#526B: 28 18
        cp      " "                                            ;#526D: FE 20
        jr      c,ASM_FETCH_LINE_BYTE                          ;#526F: 38 F1
        ld      (hl),a                                         ;#5271: 77
        inc     hl                                             ;#5272: 23
        inc     c                                              ;#5273: 0C
        djnz    ASM_FETCH_LINE_BYTE                            ;#5274: 10 EC
ASM_FETCH_LINE_SKIP_REST:
        ; Buffer full or printable-only path: read+discard bytes until null terminator
        call    MEGA_SLOT_READ_DE                              ;#5276: CD 1C FA
        inc     de                                             ;#5279: 13
        or      a                                              ;#527A: B7
        jr      nz,ASM_FETCH_LINE_SKIP_REST                    ;#527B: 20 F9
ASM_FETCH_LINE_END:
        ; Null reached: write 0 to (hl), commit DE to MEGA_ASM_PASS2_CURSOR, ret CF=0
        xor     a                                              ;#527D: AF
        ld      (hl),a                                         ;#527E: 77
        ld      (MEGA_ASM_PASS2_CURSOR),de                     ;#527F: ED 53 4F EC
        or      a                                              ;#5283: B7
        ret                                                    ;#5284: C9

ASM_FETCH_LINE_TAB:
        ; Tab (09h) handler: pad (hl) with spaces to the next 8-column boundary
        ld      a,c                                            ;#5285: 79
        and     7                                              ;#5286: E6 07
        neg                                                    ;#5288: ED 44
        add     a,8                                            ;#528A: C6 08
ASM_FETCH_LINE_TAB_LOOP:
        ; Per-space body of the TAB-expand path — write ' ', inc HL/C, loop
        ld      (hl)," "                                       ;#528C: 36 20
        inc     hl                                             ;#528E: 23
        inc     c                                              ;#528F: 0C
        dec     b                                              ;#5290: 05
        jr      z,ASM_FETCH_LINE_SKIP_REST                     ;#5291: 28 E3
        dec     a                                              ;#5293: 3D
        jr      nz,ASM_FETCH_LINE_TAB_LOOP                     ;#5294: 20 F6
        jr      ASM_FETCH_LINE_BYTE                            ;#5296: 18 CA

ASSEMBLE_LINE_INIT:
        ; Per-line init: save SP, clear EC53/54/55/57/F9F7, point iy at MEGA_ASM_BYTES_BUF
        ld      (MEGA_ASM_LINE_SP),sp                          ;#5298: ED 73 68 EC
        xor     a                                              ;#529C: AF
        ld      (MEGA_DISASM_OPCODE),a                         ;#529D: 32 57 EC
        ld      (MEGA_ASM_OPERAND_FLAG),a                      ;#52A0: 32 54 EC
        ld      (MEGA_ASM_OPC_FLAGS),a                         ;#52A3: 32 55 EC
        ld      (MEGA_ASM_IXY_DISP),a                          ;#52A6: 32 53 EC
        ld      (MEGA_ASM_LINE_FLAG),a                         ;#52A9: 32 F7 F9
        ld      iy,MEGA_ASM_BYTES_BUF                          ;#52AC: FD 21 8E EC
        ld      hl,(MEGA_DISASM_CURSOR)                        ;#52B0: 2A 5E EC
        ld      (MEGA_DISASM_INSTR_START),hl                   ;#52B3: 22 60 EC
        ld      hl,MEGA_ASM_LINE_BUF                           ;#52B6: 21 14 ED
        call    SKIP_SPACES_RAW                                ;#52B9: CD 0E 5C
        or      a                                              ;#52BC: B7
        jp      z,ASM_LINE_EMPTY                               ;#52BD: CA 41 53
        cp      ";"                                            ;#52C0: FE 3B
        jr      z,ASM_LINE_CHECK_FLAG                          ;#52C2: 28 60
        call    PARSE_LABEL_NAME                               ;#52C4: CD D9 5B
        cp      ":"                                            ;#52C7: FE 3A
        jr      nz,ASM_LINE_MNEMONIC                           ;#52C9: 20 23
        inc     b                                              ;#52CB: 04
        dec     b                                              ;#52CC: 05
        jp      z,ASM_ERROR_RAISE                              ;#52CD: CA BC 5B
        push    hl                                             ;#52D0: E5
        push    de                                             ;#52D1: D5
        push    bc                                             ;#52D2: C5
        call    ASM_LOOKUP_REG_NAME                            ;#52D3: CD 23 5E
        pop     bc                                             ;#52D6: C1
        pop     de                                             ;#52D7: D1
        pop     hl                                             ;#52D8: E1
        jp      c,ASM_ERROR_RAISE                              ;#52D9: DA BC 5B
        push    hl                                             ;#52DC: E5
        call    ASM_INSERT_OR_UPDATE_LABEL                     ;#52DD: CD 15 5C
        pop     hl                                             ;#52E0: E1
        call    SKIP_SPACES_RAW                                ;#52E1: CD 0E 5C
        or      a                                              ;#52E4: B7
        jr      z,ASM_LINE_CHECK_FLAG                          ;#52E5: 28 3D
        cp      ";"                                            ;#52E7: FE 3B
        jr      z,ASM_LINE_CHECK_FLAG                          ;#52E9: 28 39
        call    PARSE_LABEL_NAME                               ;#52EB: CD D9 5B
ASM_LINE_MNEMONIC:
        ; No-label arm — push HL, ASM_LOOKUP_MNEMONIC for the head-of-line token
        push    hl                                             ;#52EE: E5
        call    ASM_LOOKUP_MNEMONIC                            ;#52EF: CD 82 5F
        pop     hl                                             ;#52F2: E1
        ld      a,(MEGA_DISASM_OPCODE)                         ;#52F3: 3A 57 EC
        cp      1Eh                                            ;#52F6: FE 1E
        jp      nc,ASM_LINE_DB_DW                              ;#52F8: D2 58 53
        call    ASM_PARSE_OPERANDS                             ;#52FB: CD 2C 5D
        ld      hl,ASM_EMIT_DISPATCH_TABLE                     ;#52FE: 21 B8 57
        push    de                                             ;#5301: D5
        ld      a,(MEGA_DISASM_OPCODE)                         ;#5302: 3A 57 EC
        ld      e,a                                            ;#5305: 5F
        ld      d,0                                            ;#5306: 16 00
        add     hl,de                                          ;#5308: 19
        add     hl,de                                          ;#5309: 19
        pop     de                                             ;#530A: D1
        ld      a,(hl)                                         ;#530B: 7E
        inc     hl                                             ;#530C: 23
        ld      h,(hl)                                         ;#530D: 66
        ld      l,a                                            ;#530E: 6F
        push    hl                                             ;#530F: E5
        ld      hl,ASM_LINE_CHECK_FLAG                         ;#5310: 21 24 53
        ex      (sp),hl                                        ;#5313: E3
        push    hl                                             ;#5314: E5
        ld      h,b                                            ;#5315: 60
        ld      l,c                                            ;#5316: 69
        ld      a,80h                                          ;#5317: 3E 80
        ld      (MEGA_ASM_OPERAND_FLAG),a                      ;#5319: 32 54 EC
        ld      a,(MEGA_ASM_IXY_PREFIX)                        ;#531C: 3A 58 EC
        ld      b,a                                            ;#531F: 47
        inc     l                                              ;#5320: 2C
        dec     l                                              ;#5321: 2D
        ld      a,e                                            ;#5322: 7B
        ret                                                    ;#5323: C9

ASM_LINE_CHECK_FLAG:
        ; After parse: if MEGA_ASM_OPERAND_FLAG≠0 raise via 5BB9, else fall into FINALIZE
        ld      a,(MEGA_ASM_OPERAND_FLAG)                      ;#5324: 3A 54 EC
        or      a                                              ;#5327: B7
        jp      nz,ASM_ERROR_OPERAND                           ;#5328: C2 B9 5B
ASM_LINE_FINALIZE:
        ; Finalize one assembler line — call 554D, ASM_LIST_CURRENT_LINE, restore SP, ret
        call    ASM_TAPE_EMIT_LINE                             ;#532B: CD 4D 55
        call    ASM_LIST_CURRENT_LINE                          ;#532E: CD 65 56
ASM_LINE_SUCCESS_EXIT:
        ; Success-exit tail of the per-line assembler — or a (CF=0); restore SP; ret
        or      a                                              ;#5331: B7
ASM_LINE_RESTORE_SP:
        ; Restore MEGA_ASM_LINE_SP and ret — shared exit tail
        ld      sp,(MEGA_ASM_LINE_SP)                          ;#5332: ED 7B 68 EC
        ret                                                    ;#5336: C9

ASM_LINE_ERROR_EXIT:
        ; Set A=FFh, SCF, restore MEGA_ASM_LINE_SP, ret — propagate CF=1 to outer loop
        ld      a,0FFh                                         ;#5337: 3E FF
        jr      ASM_LINE_WARN_SET_CF                           ;#5339: 18 02

ASM_LINE_WARN_EXIT:
        ; A=1, CF=1 — warning-style exit (caller distinguishes 1 vs FFh)
        ld      a,1                                            ;#533B: 3E 01
ASM_LINE_WARN_SET_CF:
        ; Shared tail for both ERROR (A=FFh) and WARN (A=1) — clear Z, SCF, restore SP
        or      a                                              ;#533D: B7
        scf                                                    ;#533E: 37
        jr      ASM_LINE_RESTORE_SP                            ;#533F: 18 F1

ASM_LINE_EMPTY:
        ; Empty/blank-line tail: in PASS2, write CR to ECC4 + DISASM_PRINT_LINE, exit
        bit     0,(ix+1)                                       ;#5341: DD CB 01 46
        jr      z,ASM_LINE_EMPTY_DONE                          ;#5345: 28 0F
        call    CLEAR_OUTPUT_LINE_HL                           ;#5347: CD 45 57
        ld      a,"\r"                                         ;#534A: 3E 0D
        ld      (MEGA_DISASM_LINE_CR),a                        ;#534C: 32 C4 EC
        bit     0,(ix)                                         ;#534F: DD CB 00 46
        call    nz,DISASM_PRINT_LINE                           ;#5353: C4 8A 53
ASM_LINE_EMPTY_DONE:
        ; Pass1-or-no-listing arm of ASM_LINE_EMPTY — skip listing, jr SUCCESS_EXIT
        jr      ASM_LINE_SUCCESS_EXIT                          ;#5356: 18 D9

ASM_LINE_DB_DW:
        ; opt_type ≥ 30 path (DB/DW/DEFB/DEFM/DEFW): parse operand list, emit bytes
        ld      c,a                                            ;#5358: 4F
        call    ASM_CHECK_EOL_OR_COMMENT                       ;#5359: CD 7D 5D
        jp      z,ASM_ERROR_RAISE                              ;#535C: CA BC 5B
ASM_LINE_DB_DW_LOOP:
        ; Per-operand body — clear bit 7 of C (string-flag), call ASM_PARSE_DB_DW_OPERAND
        res     7,c                                            ;#535F: CB B9
ASM_LINE_DB_DW_PARSE:
        ; Alt entry — keeps C bit 7 (string lit) and falls into _PARSE_DB_DW_OPERAND
        call    ASM_PARSE_DB_DW_OPERAND                        ;#5361: CD E8 57
        call    ASM_EMIT_EC51                                  ;#5364: CD 77 58
        bit     0,c                                            ;#5367: CB 41
        call    z,ASM_EMIT_OP_16BIT_HI                         ;#5369: CC 8E 58
        push    hl                                             ;#536C: E5
        push    de                                             ;#536D: D5
        push    iy                                             ;#536E: FD E5
        pop     de                                             ;#5370: D1
        ld      hl,MEGA_ASM_BYTES_BUF_END                      ;#5371: 21 AC EC
        or      a                                              ;#5374: B7
        sbc     hl,de                                          ;#5375: ED 52
        pop     de                                             ;#5377: D1
        pop     hl                                             ;#5378: E1
        jp      c,ASM_ERROR_RAISE                              ;#5379: DA BC 5B
        bit     7,c                                            ;#537C: CB 79
        jr      nz,ASM_LINE_DB_DW_PARSE                        ;#537E: 20 E1
        call    ASM_CHECK_SEP_OR_END                           ;#5380: CD 72 5D
        cp      ","                                            ;#5383: FE 2C
        jr      z,ASM_LINE_DB_DW_LOOP                          ;#5385: 28 D8
        jp      ASM_LINE_CHECK_FLAG                            ;#5387: C3 24 53

DISASM_PRINT_LINE:
        ; Print MEGA_DISASM_LINE through PRINT_CHAR_DUAL until CR; manages paging
        ld      a,(DISASM_LINES_LEFT)                          ;#538A: 3A 59 EC
        or      a                                              ;#538D: B7
        call    z,DISASM_NEW_PAGE                              ;#538E: CC BB 53
        ld      hl,MEGA_DISASM_LINE                            ;#5391: 21 C3 EC
        ld      a,(MEGA_LIST_FROM_OFFSET)                      ;#5394: 3A 6B EC
        or      a                                              ;#5397: B7
        jr      z,DISASM_PRINT_LINE_LOOP                       ;#5398: 28 03
        ld      hl,MEGA_DISASM_MNEMONIC_COL                    ;#539A: 21 C9 EC
DISASM_PRINT_LINE_LOOP:
        ; Per-char body: read (hl), PRINT_CHAR_DUAL, advance HL, loop until CR
        ld      a,(hl)                                         ;#539D: 7E
        call    PRINT_CHAR_DUAL                                ;#539E: CD C4 42
        inc     hl                                             ;#53A1: 23
        cp      0Dh                                            ;#53A2: FE 0D
        jr      nz,DISASM_PRINT_LINE_LOOP                      ;#53A4: 20 F7
        bit     1,(ix)                                         ;#53A6: DD CB 00 4E
        ret     z                                              ;#53AA: C8
        ld      a,(DISASM_LINES_LEFT)                          ;#53AB: 3A 59 EC
        dec     a                                              ;#53AE: 3D
        ld      (DISASM_LINES_LEFT),a                          ;#53AF: 32 59 EC
        ret     nz                                             ;#53B2: C0
        ld      a,"\r"                                         ;#53B3: 3E 0D
        call    PRINT_CHAR_DUAL                                ;#53B5: CD C4 42
        jp      PRINT_CHAR_DUAL                                ;#53B8: C3 C4 42

DISASM_NEW_PAGE:
        ; Paging hook: print banner + decimal page number, reset lines-left counter
        bit     1,(ix)                                         ;#53BB: DD CB 00 4E
        ret     z                                              ;#53BF: C8
        ld      hl,MEGA_TOP_BANNER                             ;#53C0: 21 B4 6A
DISASM_BANNER_LOOP:
        ; Per-char banner emit loop in DISASM_NEW_PAGE
        ld      a,(hl)                                         ;#53C3: 7E
        or      a                                              ;#53C4: B7
        jr      z,DISASM_NEW_PAGE_NUMBER                       ;#53C5: 28 06
        call    PRINT_CHAR_DUAL                                ;#53C7: CD C4 42
        inc     hl                                             ;#53CA: 23
        jr      DISASM_BANNER_LOOP                             ;#53CB: 18 F6

DISASM_NEW_PAGE_NUMBER:
        ; Banner emitted (or skipped) — print page#, advance counter, reset LINES_LEFT
        ld      hl,(DISASM_PAGE_NUMBER)                        ;#53CD: 2A 5A EC
        call    PRINT_DEC_HL_PAD4                              ;#53D0: CD 85 4F
        ld      a,"\r"                                         ;#53D3: 3E 0D
        call    PRINT_CHAR_DUAL                                ;#53D5: CD C4 42
        call    PRINT_CHAR_DUAL                                ;#53D8: CD C4 42
        ld      hl,(DISASM_PAGE_NUMBER)                        ;#53DB: 2A 5A EC
        inc     hl                                             ;#53DE: 23
        ld      (DISASM_PAGE_NUMBER),hl                        ;#53DF: 22 5A EC
        ld      a,(MEGA_PAGE_HEIGHT)                           ;#53E2: 3A 00 EC
        ld      (DISASM_LINES_LEFT),a                          ;#53E5: 32 59 EC
        ret                                                    ;#53E8: C9

ASSEMBLE_PROGRESS_HOOK:
        ; Single-`ret` stub at the front of each assemble pass — patchable progress hook
        ret                                                    ;#53E9: C9

ASM_PRINT_SYMBOLS:
        ; Walk MEGA_SYM_TABLE_BASE, print each label name + address/value (PASS-2)
        ld      a,(MEGA_STATE_FLAGS)                           ;#53EA: 3A F5 F9
        and     0F0h                                           ;#53ED: E6 F0
        ret     z                                              ;#53EF: C8
        bit     5,a                                            ;#53F0: CB 6F
        jr      z,ASM_PRINT_SYMBOLS_LATCH                      ;#53F2: 28 02
        or      3                                              ;#53F4: F6 03
ASM_PRINT_SYMBOLS_LATCH:
        ; Update MEGA_STATE_FLAGS with the bit-5-conditional sticky OR
        ld      (MEGA_STATE_FLAGS),a                           ;#53F6: 32 F5 F9
        and     0D0h                                           ;#53F9: E6 D0
        ret     z                                              ;#53FB: C8
        call    ASSEMBLE_PROGRESS_HOOK                         ;#53FC: CD E9 53
        ld      a,"\r"                                         ;#53FF: 3E 0D
        ld      (MEGA_DISASM_LINE),a                           ;#5401: 32 C3 EC
        call    DISASM_PRINT_LINE                              ;#5404: CD 8A 53
        ld      de,(MEGA_SYM_TABLE_BASE)                       ;#5407: ED 5B 49 EC
ASM_PRINT_SYMBOLS_LOOP:
        ; Per-row loop: interrupt check + clear out-line
        call    CHECK_USER_INTERRUPT                           ;#540B: CD 9D 42
        jr      c,ASM_PRINT_SYMBOLS_ABORT                      ;#540E: 38 4B
        call    CLEAR_OUTPUT_LINE_HL                           ;#5410: CD 45 57
        ld      hl,MEGA_LIST_LABEL_DUMP_COL                    ;#5413: 21 BF EC
        ld      b,5                                            ;#5416: 06 05
ASM_PRINT_SYMBOLS_ROW_BIT_TEST:
        ; Per-row bit7/bit6 test of (ix) at top of dump
        bit     7,(ix)                                         ;#5418: DD CB 00 7E
        jr      nz,ASM_PRINT_SYM_BIT7                          ;#541C: 20 08
        bit     6,(ix)                                         ;#541E: DD CB 00 76
        jr      nz,ASM_PRINT_SYM_BIT6                          ;#5422: 20 4B
        jr      ASM_DUMP_SYMBOL_LOOP                           ;#5424: 18 3A

ASM_PRINT_SYM_BIT7:
        ; Bit-7-of-(ix) arm — call MEGA_SLOT_READ_DE, terminate on 0
        call    MEGA_SLOT_READ_DE                              ;#5426: CD 1C FA
        or      a                                              ;#5429: B7
        jr      z,ASM_PRINT_SYMBOLS_FLUSH                      ;#542A: 28 12
        inc     hl                                             ;#542C: 23
        inc     hl                                             ;#542D: 23
        inc     hl                                             ;#542E: 23
        inc     hl                                             ;#542F: 23
        call    EXTRACT_LABEL_NAME                             ;#5430: CD 81 54
ASM_PRINT_SYM_ADVANCE:
        ; Advance DE by 2 bytes and djnz back into BIT7 loop
        inc     de                                             ;#5433: 13
        inc     de                                             ;#5434: 13
        djnz    ASM_PRINT_SYMBOLS_ROW_BIT_TEST                 ;#5435: 10 E1
        ld      (hl),"\r"                                      ;#5437: 36 0D
        call    DISASM_PRINT_LINE                              ;#5439: CD 8A 53
        jr      ASM_PRINT_SYMBOLS_LOOP                         ;#543C: 18 CD

ASM_PRINT_SYMBOLS_FLUSH:
        ; Per-line flush: when accumulator B<5, write CR and print; fall into RESET_FLAGS
        ld      a,b                                            ;#543E: 78
        cp      5                                              ;#543F: FE 05
        jr      z,ASM_RESET_LABEL_FLAGS                        ;#5441: 28 05
        ld      (hl),"\r"                                      ;#5443: 36 0D
        call    DISASM_PRINT_LINE                              ;#5445: CD 8A 53
ASM_RESET_LABEL_FLAGS:
        ; Walk MEGA_SYM_TABLE_BASE clearing bit 7 of each name byte (unprinted flag)
        ld      hl,(MEGA_SYM_TABLE_BASE)                       ;#5448: 2A 49 EC
        ld      bc,0Ah                                         ;#544B: 01 0A 00
ASM_RESET_LABEL_FLAGS_LOOP:
        ; Per-entry walk clearing bit 7 of symbol name byte
        call    MEGA_SLOT_READ_HL                              ;#544E: CD 16 FA
        or      a                                              ;#5451: B7
        ret     z                                              ;#5452: C8
        res     7,a                                            ;#5453: CB BF
        call    MEGA_SLOT_WRITE                                ;#5455: CD 10 FA
        add     hl,bc                                          ;#5458: 09
        jr      ASM_RESET_LABEL_FLAGS_LOOP                     ;#5459: 18 F3

ASM_PRINT_SYMBOLS_ABORT:
        ; User-interrupt exit — RESET_FLAGS then scf+ret so caller sees the abort
        call    ASM_RESET_LABEL_FLAGS                          ;#545B: CD 48 54
        scf                                                    ;#545E: 37
        ret                                                    ;#545F: C9

ASM_DUMP_SYMBOL_LOOP:
        ; Symbol-table walk: CHECK_USER_INTERRUPT, ASM_FIND_NEXT_LABEL, repeat
        call    CHECK_USER_INTERRUPT                           ;#5460: CD 9D 42
        jr      c,ASM_PRINT_SYMBOLS_ABORT                      ;#5463: 38 F6
        call    ASM_FIND_NEXT_LABEL                            ;#5465: CD B4 54
        jr      nc,ASM_RESET_LABEL_FLAGS                       ;#5468: 30 DE
        call    ASM_DUMP_SYMBOL_LINE                           ;#546A: CD 03 55
        jr      ASM_DUMP_SYMBOL_LOOP                           ;#546D: 18 F1

ASM_PRINT_SYM_BIT6:
        ; Bit-6-of-(ix) arm — find next mark-eligible label via ASM_FIND_NEXT_LABEL
        push    bc                                             ;#546F: C5
        push    hl                                             ;#5470: E5
        call    ASM_FIND_NEXT_LABEL                            ;#5471: CD B4 54
        pop     hl                                             ;#5474: E1
        pop     bc                                             ;#5475: C1
        jr      nc,ASM_PRINT_SYMBOLS_FLUSH                     ;#5476: 30 C6
        inc     hl                                             ;#5478: 23
        inc     hl                                             ;#5479: 23
        inc     hl                                             ;#547A: 23
        inc     hl                                             ;#547B: 23
        call    MARK_AND_COPY_LABEL_HEAD                       ;#547C: CD A3 54
        jr      ASM_PRINT_SYM_ADVANCE                          ;#547F: 18 B2

EXTRACT_LABEL_NAME:
        ; Copy 6 bytes (HL→DE) with bit-7 mask — extract a symbol's name to a scratch
        push    bc                                             ;#5481: C5
        ld      b,6                                            ;#5482: 06 06
        ex      de,hl                                          ;#5484: EB
EXTRACT_LABEL_NAME_LOOP:
        ; Per-byte copy: MEGA_SLOT_READ_HL, mask bit 7, store at (de), advance, djnz
        call    MEGA_SLOT_READ_HL                              ;#5485: CD 16 FA
        and     7Fh                                            ;#5488: E6 7F
        ld      (de),a                                         ;#548A: 12
        inc     hl                                             ;#548B: 23
        inc     de                                             ;#548C: 13
        djnz    EXTRACT_LABEL_NAME_LOOP                        ;#548D: 10 F6
        pop     bc                                             ;#548F: C1
        ex      de,hl                                          ;#5490: EB
        inc     hl                                             ;#5491: 23
        inc     de                                             ;#5492: 13
        call    MEGA_SLOT_READ_DE                              ;#5493: CD 1C FA
        call    STORE_HEX_A_AT_HL                              ;#5496: CD 41 56
        dec     de                                             ;#5499: 1B
        call    MEGA_SLOT_READ_DE                              ;#549A: CD 1C FA
        call    STORE_HEX_A_AT_HL                              ;#549D: CD 41 56
        inc     de                                             ;#54A0: 13
        inc     de                                             ;#54A1: 13
        ret                                                    ;#54A2: C9

MARK_AND_COPY_LABEL_HEAD:
        ; Copy 1st name byte (HL→DE), set bit 7 on source (mark printed); 5 more via 5485
        ex      de,hl                                          ;#54A3: EB
        call    MEGA_SLOT_READ_HL                              ;#54A4: CD 16 FA
        ld      (de),a                                         ;#54A7: 12
        set     7,a                                            ;#54A8: CB FF
        call    MEGA_SLOT_WRITE                                ;#54AA: CD 10 FA
        inc     hl                                             ;#54AD: 23
        inc     de                                             ;#54AE: 13
        push    bc                                             ;#54AF: C5
        ld      b,5                                            ;#54B0: 06 05
        jr      EXTRACT_LABEL_NAME_LOOP                        ;#54B2: 18 D1

ASM_FIND_NEXT_LABEL:
        ; Walk MEGA_SYM_TABLE_BASE for next unprinted label; CF=1 found (DE/HL), CF=0 done
        ld      bc,0Ah                                         ;#54B4: 01 0A 00
        ld      hl,(MEGA_SYM_TABLE_BASE)                       ;#54B7: 2A 49 EC
ASM_FIND_NEXT_LABEL_LOOP:
        ; Per-record scan in MEGA_SYM_TABLE_BASE walker
        call    MEGA_SLOT_READ_HL                              ;#54BA: CD 16 FA
        or      a                                              ;#54BD: B7
        jr      z,ASM_FIND_LABEL_DONE                          ;#54BE: 28 2B
        jp      p,ASM_FIND_LABEL_RECORD                        ;#54C0: F2 C6 54
        add     hl,bc                                          ;#54C3: 09
        jr      ASM_FIND_NEXT_LABEL_LOOP                       ;#54C4: 18 F4

ASM_FIND_LABEL_RECORD:
        ; Save HL→DE as candidate record, fall into per-reference scan
        ld      d,h                                            ;#54C6: 54
        ld      e,l                                            ;#54C7: 5D
ASM_FIND_LABEL_SCAN:
        ; Per-reference walk: read next byte, m=continue, name-match compares vs DE
        add     hl,bc                                          ;#54C8: 09
        call    MEGA_SLOT_READ_HL                              ;#54C9: CD 16 FA
        or      a                                              ;#54CC: B7
        jp      m,ASM_FIND_LABEL_SCAN                          ;#54CD: FA C8 54
        scf                                                    ;#54D0: 37
        jr      z,ASM_FIND_LABEL_DONE                          ;#54D1: 28 18
        push    de                                             ;#54D3: D5
        push    hl                                             ;#54D4: E5
ASM_FIND_LABEL_NAME_CMP:
        ; Per-byte name compare loop (HL vs DE) in scan
        call    MEGA_SLOT_READ_HL                              ;#54D5: CD 16 FA
        push    bc                                             ;#54D8: C5
        ld      b,a                                            ;#54D9: 47
        call    MEGA_SLOT_READ_DE                              ;#54DA: CD 1C FA
        cp      b                                              ;#54DD: B8
        pop     bc                                             ;#54DE: C1
        jr      nz,ASM_FIND_LABEL_NAME_END                     ;#54DF: 20 04
        inc     de                                             ;#54E1: 13
        inc     hl                                             ;#54E2: 23
        jr      ASM_FIND_LABEL_NAME_CMP                        ;#54E3: 18 F0

ASM_FIND_LABEL_NAME_END:
        ; Per-byte compare miss — pop saved HL/DE, on CF retry scan, else save record
        pop     hl                                             ;#54E5: E1
        pop     de                                             ;#54E6: D1
        jr      c,ASM_FIND_LABEL_SCAN                          ;#54E7: 38 DF
        jr      ASM_FIND_LABEL_RECORD                          ;#54E9: 18 DB

ASM_FIND_LABEL_DONE:
        ; Bare `ret` — shared tail; CF=1 on match (scf at 54D0), CF=0 on EOT
        ret                                                    ;#54EB: C9

ASM_CLEAR_SYMBOL_REFS:
        ; Walk symbol table from SYM_TABLE_BASE; zero the 2-byte reference-list head
        ld      hl,(MEGA_SYM_TABLE_BASE)                       ;#54EC: 2A 49 EC
        ld      bc,8                                           ;#54EF: 01 08 00
ASM_CLEAR_SYMBOL_REFS_LOOP:
        ; Per-symbol loop zeroing the ref-list head bytes
        call    MEGA_SLOT_READ_HL                              ;#54F2: CD 16 FA
        or      a                                              ;#54F5: B7
        ret     z                                              ;#54F6: C8
        add     hl,bc                                          ;#54F7: 09
        xor     a                                              ;#54F8: AF
        call    MEGA_SLOT_WRITE                                ;#54F9: CD 10 FA
        inc     hl                                             ;#54FC: 23
        call    MEGA_SLOT_WRITE                                ;#54FD: CD 10 FA
        inc     hl                                             ;#5500: 23
        jr      ASM_CLEAR_SYMBOL_REFS_LOOP                     ;#5501: 18 EF

ASM_DUMP_SYMBOL_LINE:
        ; Render one symbol's row: label name + up to 10 chained reference addresses
        call    CLEAR_OUTPUT_LINE_HL                           ;#5503: CD 45 57
        ld      hl,MEGA_DISASM_LINE                            ;#5506: 21 C3 EC
        call    MARK_AND_COPY_LABEL_HEAD                       ;#5509: CD A3 54
        call    READ_USER_WORD_AT_DE                           ;#550C: CD 3F 55
        jr      z,ASM_DUMP_FINISH_LINE                         ;#550F: 28 29
ASM_DUMP_SYMBOL_REFS_LOOP:
        ; Per-reference-chunk loop rendering up-to-10 addrs
        ld      hl,MEGA_LIST_REFS_COL                          ;#5511: 21 CF EC
        ld      b,0Ah                                          ;#5514: 06 0A
ASM_DUMP_SYMBOL_REFS_BODY:
        ; Per-ref body: store hex pair of chained addr in HL
        inc     hl                                             ;#5516: 23
        push    de                                             ;#5517: D5
        inc     de                                             ;#5518: 13
        inc     de                                             ;#5519: 13
        inc     de                                             ;#551A: 13
        call    MEGA_SLOT_READ_DE                              ;#551B: CD 1C FA
        call    STORE_HEX_A_AT_HL                              ;#551E: CD 41 56
        dec     de                                             ;#5521: 1B
        call    MEGA_SLOT_READ_DE                              ;#5522: CD 1C FA
        call    STORE_HEX_A_AT_HL                              ;#5525: CD 41 56
        pop     de                                             ;#5528: D1
        call    READ_USER_WORD_AT_DE                           ;#5529: CD 3F 55
        jr      z,ASM_DUMP_FINISH_LINE                         ;#552C: 28 0C
        djnz    ASM_DUMP_SYMBOL_REFS_BODY                      ;#552E: 10 E6
        push    de                                             ;#5530: D5
        call    ASM_DUMP_FINISH_LINE                           ;#5531: CD 3A 55
        call    CLEAR_OUTPUT_LINE_HL                           ;#5534: CD 45 57
        pop     de                                             ;#5537: D1
        jr      ASM_DUMP_SYMBOL_REFS_LOOP                      ;#5538: 18 D7

ASM_DUMP_FINISH_LINE:
        ; Common tail: write CR at (HL), jp DISASM_PRINT_LINE
        ld      (hl),"\r"                                      ;#553A: 36 0D
        jp      DISASM_PRINT_LINE                              ;#553C: C3 8A 53

READ_USER_WORD_AT_DE:
        ; Read 16-bit word at (DE) into DE (slot-aware, HL preserved); Z=1 if word is zero
        push    hl                                             ;#553F: E5
        ex      de,hl                                          ;#5540: EB
        call    MEGA_SLOT_READ_HL                              ;#5541: CD 16 FA
        ld      e,a                                            ;#5544: 5F
        inc     hl                                             ;#5545: 23
        call    MEGA_SLOT_READ_HL                              ;#5546: CD 16 FA
        ld      d,a                                            ;#5549: 57
        or      e                                              ;#554A: B3
        pop     hl                                             ;#554B: E1
        ret                                                    ;#554C: C9

ASM_TAPE_EMIT_LINE:
        ; PASS2 + tape-mode: emit the line's assembled bytes to cassette
        bit     0,(ix+1)                                       ;#554D: DD CB 01 46
        ret     z                                              ;#5551: C8
        bit     3,(ix)                                         ;#5552: DD CB 00 5E
        ret     z                                              ;#5556: C8
        ld      a,(MEGA_DISASM_OPCODE)                         ;#5557: 3A 57 EC
        cp      17h                                            ;#555A: FE 17
        ret     z                                              ;#555C: C8
        cp      14h                                            ;#555D: FE 14
        jr      z,ASM_TAPE_START_RECORD                        ;#555F: 28 22
        cp      16h                                            ;#5561: FE 16
        jr      z,ASM_TAPE_START_RECORD                        ;#5563: 28 1E
        cp      15h                                            ;#5565: FE 15
        jr      nz,ASM_TAPE_EMIT_BUFFERED                      ;#5567: 20 05
        ld      a,(MEGA_ASM_LINE_FLAG)                         ;#5569: 3A F7 F9
        or      a                                              ;#556C: B7
        ret     z                                              ;#556D: C8
ASM_TAPE_EMIT_BUFFERED:
        ; Per-byte buffered tape emit: walk MEGA_ASM_BYTES_BUF[0..n], call _EMIT_BYTE
        ld      hl,(MEGA_DISASM_INSTR_START)                   ;#556E: 2A 60 EC
        ld      de,(MEGA_DISASM_CURSOR)                        ;#5571: ED 5B 5E EC
        ld      bc,MEGA_ASM_BYTES_BUF                          ;#5575: 01 8E EC
ASM_TAPE_EMIT_BUFFERED_LOOP:
        ; Per-byte loop: compare E-L, emit byte, advance
        ld      a,e                                            ;#5578: 7B
        sub     l                                              ;#5579: 95
        ret     z                                              ;#557A: C8
        ld      a,(bc)                                         ;#557B: 0A
        call    ASM_TAPE_EMIT_BYTE                             ;#557C: CD CD 55
        inc     hl                                             ;#557F: 23
        inc     bc                                             ;#5580: 03
        jr      ASM_TAPE_EMIT_BUFFERED_LOOP                    ;#5581: 18 F5

ASM_TAPE_START_RECORD:
        ; Start a new tape record (header + counters) when buffer threshold hit
        push    bc                                             ;#5583: C5
        push    hl                                             ;#5584: E5
        ld      hl,MEGA_TAPE_REC_COUNT                         ;#5585: 21 79 EC
        ld      a,(hl)                                         ;#5588: 7E
        or      a                                              ;#5589: B7
        jr      z,ASM_TAPE_RECORD_DONE                         ;#558A: 28 3E
        ld      a,(MEGA_ASM_PASS1_FLAG_LO)                     ;#558C: 3A 6C EC
        or      a                                              ;#558F: B7
        ld      a,0FFh                                         ;#5590: 3E FF
        ld      (MEGA_ASM_PASS1_FLAG_LO),a                     ;#5592: 32 6C EC
        push    af                                             ;#5595: F5
        call    z,CASSETTE_TAPOON_AF                           ;#5596: CC DD 42
        pop     af                                             ;#5599: F1
        call    nz,BIOS_TAPOON_PRESERVE                        ;#559A: C4 DE 42
        ld      a,":"                                          ;#559D: 3E 3A
        call    CASSETTE_PUT_BYTE                              ;#559F: CD FB 42
        ld      c,0                                            ;#55A2: 0E 00
        ld      b,(hl)                                         ;#55A4: 46
        call    TAPE_WRITE_HEX_BYTE_FROM_HL                    ;#55A5: CD 2C 56
        inc     hl                                             ;#55A8: 23
        call    TAPE_WRITE_HEX_BYTE_FROM_HL                    ;#55A9: CD 2C 56
        dec     hl                                             ;#55AC: 2B
        dec     hl                                             ;#55AD: 2B
        call    TAPE_WRITE_HEX_BYTE_FROM_HL                    ;#55AE: CD 2C 56
        inc     hl                                             ;#55B1: 23
        xor     a                                              ;#55B2: AF
        call    TAPE_WRITE_HEX_BYTE_FROM_A                     ;#55B3: CD 2E 56
ASM_TAPE_WRITE_BODY_LOOP:
        ; Loop emitting body byte hex pairs into tape record
        call    TAPE_WRITE_HEX_BYTE_FROM_HL                    ;#55B6: CD 2C 56
        djnz    ASM_TAPE_WRITE_BODY_LOOP                       ;#55B9: 10 FB
        call    TAPE_WRITE_CHECKSUM                            ;#55BB: CD 1D 56
        push    de                                             ;#55BE: D5
        call    TAPE_DELAY_2                                   ;#55BF: CD 80 4B
        pop     de                                             ;#55C2: D1
        call    CASSETTE_STOP_WRITE                            ;#55C3: CD 3E 43
        xor     a                                              ;#55C6: AF
        ld      (MEGA_TAPE_REC_COUNT),a                        ;#55C7: 32 79 EC
ASM_TAPE_RECORD_DONE:
        ; Tail of ASM_TAPE_START_RECORD — pop saved HL/BC and ret
        pop     hl                                             ;#55CA: E1
        pop     bc                                             ;#55CB: C1
        ret                                                    ;#55CC: C9

ASM_TAPE_EMIT_BYTE:
        ; Append a byte to the tape record buffer; flush via 5583 when full
        push    af                                             ;#55CD: F5
        push    bc                                             ;#55CE: C5
        push    hl                                             ;#55CF: E5
        push    af                                             ;#55D0: F5
        ld      a,(MEGA_TAPE_REC_COUNT)                        ;#55D1: 3A 79 EC
        or      a                                              ;#55D4: B7
        jr      nz,ASM_TAPE_EMIT_APPEND                        ;#55D5: 20 03
        ld      (MEGA_TAPE_REC_ADDR),hl                        ;#55D7: 22 7A EC
ASM_TAPE_EMIT_APPEND:
        ; Buffer non-empty (or initialized) — compute slot, store byte, bump count
        ld      hl,MEGA_TAPE_REC_BUF                           ;#55DA: 21 7C EC
        ld      b,0                                            ;#55DD: 06 00
        ld      c,a                                            ;#55DF: 4F
        add     hl,bc                                          ;#55E0: 09
        pop     af                                             ;#55E1: F1
        ld      (hl),a                                         ;#55E2: 77
        ld      a,c                                            ;#55E3: 79
        inc     a                                              ;#55E4: 3C
        ld      (MEGA_TAPE_REC_COUNT),a                        ;#55E5: 32 79 EC
        cp      10h                                            ;#55E8: FE 10
        call    nc,ASM_TAPE_START_RECORD                       ;#55EA: D4 83 55
        pop     hl                                             ;#55ED: E1
        pop     bc                                             ;#55EE: C1
        pop     af                                             ;#55EF: F1
        ret                                                    ;#55F0: C9

TAPE_WRITE_EOF:
        ; Emit Intel-Hex EOF record (":0000…00<crlf>") then delay and stop the cassette
        bit     0,(ix+1)                                       ;#55F1: DD CB 01 46
        ret     z                                              ;#55F5: C8
        bit     3,(ix)                                         ;#55F6: DD CB 00 5E
        ret     z                                              ;#55FA: C8
        call    ASM_TAPE_START_RECORD                          ;#55FB: CD 83 55
        call    BIOS_TAPOON_PRESERVE                           ;#55FE: CD DE 42
        ld      a,":"                                          ;#5601: 3E 3A
        call    CASSETTE_PUT_BYTE                              ;#5603: CD FB 42
        ld      b,8                                            ;#5606: 06 08
TAPE_WRITE_EOF_BYTE:
        ; Emit 8 zero-hex bytes inside the EOF Intel-Hex record
        xor     a                                              ;#5608: AF
        call    TAPE_WRITE_HEX_BYTE_FROM_A                     ;#5609: CD 2E 56
        djnz    TAPE_WRITE_EOF_BYTE                            ;#560C: 10 FA
        ld      a,1Ah                                          ;#560E: 3E 1A
        call    CASSETTE_PUT_BYTE                              ;#5610: CD FB 42
        call    TAPE_WRITE_CRLF                                ;#5613: CD 22 56
        call    TAPE_DELAY_2                                   ;#5616: CD 80 4B
        call    CASSETTE_STOP_WRITE                            ;#5619: CD 3E 43
        ret                                                    ;#561C: C9

TAPE_WRITE_CHECKSUM:
        ; Emit two's-complement checksum byte (xor a / sub c)
        xor     a                                              ;#561D: AF
        sub     c                                              ;#561E: 91
        call    TAPE_WRITE_HEX_BYTE_FROM_A                     ;#561F: CD 2E 56
TAPE_WRITE_CRLF:
        ; Emit CR+LF to cassette via CASSETTE_PUT_BYTE — terminates a tape ASCII line
        ld      a,"\r"                                         ;#5622: 3E 0D
        call    CASSETTE_PUT_BYTE                              ;#5624: CD FB 42
        ld      a,"\n"                                         ;#5627: 3E 0A
        jp      CASSETTE_PUT_BYTE                              ;#5629: C3 FB 42

TAPE_WRITE_HEX_BYTE_FROM_HL:
        ; Read byte from (HL)++, add to checksum C, emit as 2 hex chars to cassette
        ld      a,(hl)                                         ;#562C: 7E
        inc     hl                                             ;#562D: 23
TAPE_WRITE_HEX_BYTE_FROM_A:
        ; Add A to checksum C, emit A as 2 hex chars to cassette
        push    af                                             ;#562E: F5
        add     a,c                                            ;#562F: 81
        ld      c,a                                            ;#5630: 4F
        pop     af                                             ;#5631: F1
        push    af                                             ;#5632: F5
        rrca                                                   ;#5633: 0F
        rrca                                                   ;#5634: 0F
        rrca                                                   ;#5635: 0F
        rrca                                                   ;#5636: 0F
        call    TAPE_WRITE_HEX_NIBBLE                          ;#5637: CD 3B 56
        pop     af                                             ;#563A: F1
TAPE_WRITE_HEX_NIBBLE:
        ; Emit low 4 bits of A as one hex digit to cassette via CASSETTE_PUT_BYTE
        call    NIBBLE_TO_ASCII                                ;#563B: CD B2 50
        jp      CASSETTE_PUT_BYTE                              ;#563E: C3 FB 42

STORE_HEX_A_AT_HL:
        ; Write A as 2 hex digits to (HL), advance HL by 2 (10 callers in save paths)
        push    af                                             ;#5641: F5
        rrca                                                   ;#5642: 0F
        rrca                                                   ;#5643: 0F
        rrca                                                   ;#5644: 0F
        rrca                                                   ;#5645: 0F
        call    STORE_HEX_LOW_NIBBLE                           ;#5646: CD 4A 56
        pop     af                                             ;#5649: F1
STORE_HEX_LOW_NIBBLE:
        ; Tail: NIBBLE_TO_ASCII, store at (HL), inc HL, ret
        call    NIBBLE_TO_ASCII                                ;#564A: CD B2 50
        ld      (hl),a                                         ;#564D: 77
        inc     hl                                             ;#564E: 23
        ret                                                    ;#564F: C9

STORE_HEX_WORD_AT_HL:
        ; Write 16-bit (DE+1)/(DE) into (HL) as 4 hex digits via STORE_HEX_A_AT_HL
        inc     de                                             ;#5650: 13
        ld      a,(de)                                         ;#5651: 1A
        call    STORE_HEX_A_AT_HL                              ;#5652: CD 41 56
        dec     de                                             ;#5655: 1B
        ld      a,(de)                                         ;#5656: 1A
        jp      STORE_HEX_A_AT_HL                              ;#5657: C3 41 56

STORE_DEC_HL_TO_LINE_5:
        ; Render HL as right-aligned 5-digit decimal at MEGA_DISASM_LINE via STORE_DEC_PAD
        ld      c,5                                            ;#565A: 0E 05
        call    PUSH_DIGITS_HL                                 ;#565C: CD 6A 4F
        ld      hl,MEGA_DISASM_LINE                            ;#565F: 21 C3 EC
        jp      STORE_DEC_PAD_LOOP                             ;#5662: C3 B3 4F

ASM_LIST_CURRENT_LINE:
        ; Pass-2 listing printer: build the line via ASM_FORMAT_LISTING_LINE then echo
        bit     0,(ix+1)                                       ;#5665: DD CB 01 46
        ret     z                                              ;#5669: C8
        xor     a                                              ;#566A: AF
        ld      (MEGA_ASM_OP_SIGN),a                           ;#566B: 32 56 EC
        ld      a,(MEGA_ASM_LINE_FLAG)                         ;#566E: 3A F7 F9
        or      a                                              ;#5671: B7
        jr      nz,ASM_LIST_LINE_BODY                          ;#5672: 20 05
        bit     0,(ix)                                         ;#5674: DD CB 00 46
        ret     z                                              ;#5678: C8
ASM_LIST_LINE_BODY:
        ; ASM_LINE_FLAG nonzero or bit-0 set — clear out-line, format the line
        call    CLEAR_OUTPUT_LINE_HL                           ;#5679: CD 45 57
        ld      hl,(MEGA_ASM_CURRENT_LINE)                     ;#567C: 2A 62 EC
        call    STORE_DEC_HL_TO_LINE_5                         ;#567F: CD 5A 56
        ld      hl,MEGA_ASM_LINE_BUF                           ;#5682: 21 14 ED
        call    SKIP_SPACES_RAW                                ;#5685: CD 0E 5C
        ex      de,hl                                          ;#5688: EB
        cp      ";"                                            ;#5689: FE 3B
        jr      z,ASM_LIST_COMMENT_ONLY                        ;#568B: 28 46
        xor     a                                              ;#568D: AF
        ld      (MEGA_ASM_OP_SIGN),a                           ;#568E: 32 56 EC
        ld      iy,MEGA_ASM_BYTES_BUF                          ;#5691: FD 21 8E EC
        call    ASM_FORMAT_LISTING_LINE                        ;#5695: CD 50 57
        ld      hl,MEGA_ASM_LINE_BUF                           ;#5698: 21 14 ED
        push    hl                                             ;#569B: E5
        call    PARSE_LABEL_NAME                               ;#569C: CD D9 5B
        pop     de                                             ;#569F: D1
        cp      ":"                                            ;#56A0: FE 3A
        jr      nz,ASM_LIST_NO_LABEL                           ;#56A2: 20 08
        ld      hl,MEGA_LIST_LABEL_COL                         ;#56A4: 21 DA EC
        ld      b,0                                            ;#56A7: 06 00
        call    COPY_SRC_TOKEN_TO_LINE                         ;#56A9: CD 0D 57
ASM_LIST_NO_LABEL:
        ; No label-on-line — pour into MEGA_LIST_MNEM_COL instead of LABEL_COL
        ld      hl,MEGA_LIST_MNEM_COL                          ;#56AC: 21 E1 EC
        ld      b," "                                          ;#56AF: 06 20
        call    COPY_SRC_TOKEN_TO_LINE                         ;#56B1: CD 0D 57
        ld      hl,MEGA_LIST_OPND_COL                          ;#56B4: 21 E6 EC
        ld      b,0                                            ;#56B7: 06 00
        call    COPY_SRC_TOKEN_TO_LINE                         ;#56B9: CD 0D 57
LISTING_TRIM_TRAILING_SPACES:
        ; Walk HL backwards past 20h spaces (post-token trim of listing line)
        ld      a,(hl)                                         ;#56BC: 7E
        cp      " "                                            ;#56BD: FE 20
        jr      nz,LISTING_TRIM_BOUNDS_CHECK                   ;#56BF: 20 03
        dec     hl                                             ;#56C1: 2B
        jr      LISTING_TRIM_TRAILING_SPACES                   ;#56C2: 18 F8

LISTING_TRIM_BOUNDS_CHECK:
        ; Trim complete — clamp HL to MEGA_LIST_MNEM_COL minimum (no underflow)
        ld      bc,MEGA_LIST_COMMENT_COL                       ;#56C4: 01 F4 EC
        push    hl                                             ;#56C7: E5
        or      a                                              ;#56C8: B7
        sbc     hl,bc                                          ;#56C9: ED 42
        pop     hl                                             ;#56CB: E1
        inc     hl                                             ;#56CC: 23
        jr      nc,LISTING_TRIM_CLAMP_DONE                     ;#56CD: 30 02
        ld      h,b                                            ;#56CF: 60
        ld      l,c                                            ;#56D0: 69
LISTING_TRIM_CLAMP_DONE:
        ; After clamp — fall into the comment-or-CR finalization
        jr      ASM_LIST_COPY_LABEL_INIT                       ;#56D1: 18 03

ASM_LIST_COMMENT_ONLY:
        ; Line was just `;`-comment — short-circuit straight to listing emit
        ld      hl,MEGA_LIST_LABEL_COL                         ;#56D3: 21 DA EC
ASM_LIST_COPY_LABEL_INIT:
        ; Init BC=ED12h bound before ASM_LIST_LABEL_BODY copy
        ld      bc,MEGA_LIST_LABEL_END                         ;#56D6: 01 12 ED
        ld      a,(MEGA_LIST_FROM_OFFSET)                      ;#56D9: 3A 6B EC
        or      a                                              ;#56DC: B7
        jr      z,ASM_LIST_LABEL_BODY                          ;#56DD: 28 03
        ld      bc,MEGA_LIST_LABEL_END_LONG                    ;#56DF: 01 18 ED
ASM_LIST_LABEL_BODY:
        ; Per-char copy of label name into MEGA_LIST_BUF; loops back if not overflow
        ld      a,(de)                                         ;#56E2: 1A
        inc     de                                             ;#56E3: 13
        or      a                                              ;#56E4: B7
        jr      z,LISTING_TERMINATE_LINE                       ;#56E5: 28 08
        ld      (hl),a                                         ;#56E7: 77
        inc     hl                                             ;#56E8: 23
        push    hl                                             ;#56E9: E5
        sbc     hl,bc                                          ;#56EA: ED 42
        pop     hl                                             ;#56EC: E1
        jr      c,ASM_LIST_LABEL_BODY                          ;#56ED: 38 F3
LISTING_TERMINATE_LINE:
        ; Write CR at (HL), print listing line if flagged, recurse for second half
        ld      (hl),"\r"                                      ;#56EF: 36 0D
        bit     0,(ix)                                         ;#56F1: DD CB 00 46
        jr      nz,LISTING_TERM_PRINT                          ;#56F5: 20 06
        ld      a,(MEGA_ASM_LINE_FLAG)                         ;#56F7: 3A F7 F9
        or      a                                              ;#56FA: B7
        jr      z,LISTING_TERM_OP_SIGN                         ;#56FB: 28 03
LISTING_TERM_PRINT:
        ; Bit-0 or LINE_FLAG set — DISASM_PRINT_LINE the assembled listing line
        call    DISASM_PRINT_LINE                              ;#56FD: CD 8A 53
LISTING_TERM_OP_SIGN:
        ; After print: if MEGA_ASM_OP_SIGN set, re-clear+format+recurse for cont line
        ld      a,(MEGA_ASM_OP_SIGN)                           ;#5700: 3A 56 EC
        or      a                                              ;#5703: B7
        ret     z                                              ;#5704: C8
        call    CLEAR_OUTPUT_LINE_HL                           ;#5705: CD 45 57
        call    ASM_FORMAT_LISTING_LINE                        ;#5708: CD 50 57
        jr      LISTING_TERMINATE_LINE                         ;#570B: 18 E2

COPY_SRC_TOKEN_TO_LINE:
        ; Copy a source-text token (DE) to (HL); stops on B-terminator, ';' or NUL
        ex      de,hl                                          ;#570D: EB
        call    SKIP_SPACES_RAW                                ;#570E: CD 0E 5C
        ex      de,hl                                          ;#5711: EB
COPY_SRC_TOKEN_LOOP:
        ; Per-byte body: read source char, range/terminator check, store, advance
        ld      a,(de)                                         ;#5712: 1A
        or      a                                              ;#5713: B7
        jr      z,COPY_SRC_TOKEN_END_EOL                       ;#5714: 28 27
        cp      ";"                                            ;#5716: FE 3B
        jr      z,COPY_SRC_TOKEN_END_CMT                       ;#5718: 28 27
        cp      b                                              ;#571A: B8
        ret     z                                              ;#571B: C8
        bit     5,b                                            ;#571C: CB 68
        jr      z,COPY_SRC_TOKEN_STORE                         ;#571E: 28 06
        cp      "A"                                            ;#5720: FE 41
        ret     c                                              ;#5722: D8
        cp      "Z"+1                                          ;#5723: FE 5B
        ret     nc                                             ;#5725: D0
COPY_SRC_TOKEN_STORE:
        ; Range-check passed — store char at (hl), inc, special-case ':' and '
        ld      (hl),a                                         ;#5726: 77
        inc     hl                                             ;#5727: 23
        inc     de                                             ;#5728: 13
        cp      ":"                                            ;#5729: FE 3A
        ret     z                                              ;#572B: C8
        cp      "'"                                            ;#572C: FE 27
        jr      nz,COPY_SRC_TOKEN_LOOP                         ;#572E: 20 E2
COPY_SRC_TOKEN_QUOTED:
        ; Inside '..' literal — copy chars verbatim until matching ' or NUL
        ld      a,(de)                                         ;#5730: 1A
        inc     de                                             ;#5731: 13
        or      a                                              ;#5732: B7
        jr      z,COPY_SRC_TOKEN_END_EOL                       ;#5733: 28 08
        ld      (hl),a                                         ;#5735: 77
        inc     hl                                             ;#5736: 23
        cp      "'"                                            ;#5737: FE 27
        jr      nz,COPY_SRC_TOKEN_QUOTED                       ;#5739: 20 F5
        jr      COPY_SRC_TOKEN_LOOP                            ;#573B: 18 D5

COPY_SRC_TOKEN_END_EOL:
        ; EOL/null reached: pop scratch AF, jp LISTING_TERMINATE_LINE
        pop     af                                             ;#573D: F1
        jp      LISTING_TERMINATE_LINE                         ;#573E: C3 EF 56

COPY_SRC_TOKEN_END_CMT:
        ; Comment `;` found: pop, jp LISTING_TRIM_TRAILING_SPACES then terminate
        pop     af                                             ;#5741: F1
        jp      LISTING_TRIM_TRAILING_SPACES                   ;#5742: C3 BC 56

CLEAR_OUTPUT_LINE_HL:
        ; Fill MEGA_DISASM_LINE with 80 spaces (HL/djnz variant; HL-cursor callers)
        ld      hl,MEGA_DISASM_LINE                            ;#5745: 21 C3 EC
        ld      b,50h                                          ;#5748: 06 50
CLEAR_OUTPUT_LINE_HL_BODY:
        ; Fill body: store space at (hl), inc HL, djnz
        ld      (hl)," "                                       ;#574A: 36 20
        inc     hl                                             ;#574C: 23
        djnz    CLEAR_OUTPUT_LINE_HL_BODY                      ;#574D: 10 FB
        ret                                                    ;#574F: C9

ASM_FORMAT_LISTING_LINE:
        ; Build per-line listing in MEGA_DISASM_LINE based on MEGA_DISASM_OPCODE category
        ld      a,(MEGA_DISASM_OPCODE)                         ;#5750: 3A 57 EC
        ld      b,a                                            ;#5753: 47
        ld      hl,MEGA_DISASM_OPERAND_COL                     ;#5754: 21 D1 EC
        ld      a,b                                            ;#5757: 78
        cp      14h                                            ;#5758: FE 14
        jr      z,ASM_LIST_FMT_DISPATCH                        ;#575A: 28 0A
        ld      hl,MEGA_LIST_ADDR_COL                          ;#575C: 21 CC EC
        ld      de,MEGA_DISASM_INSTR_START                     ;#575F: 11 60 EC
        call    STORE_HEX_WORD_AT_HL                           ;#5762: CD 50 56
        inc     hl                                             ;#5765: 23
ASM_LIST_FMT_DISPATCH:
        ; Dispatch on opcode-category byte: 14h=skip-addr, 15-17h=skip-bytes, else dump-4
        ld      a,b                                            ;#5766: 78
        cp      14h                                            ;#5767: FE 14
        jr      z,ASM_LIST_EMIT_FLAGS                          ;#5769: 28 25
        cp      15h                                            ;#576B: FE 15
        jr      c,ASM_LIST_FMT_DUMP4                           ;#576D: 38 04
        cp      18h                                            ;#576F: FE 18
        jr      c,ASM_LIST_EMIT_FLAGS                          ;#5771: 38 1D
ASM_LIST_FMT_DUMP4:
        ; Default arm — dump up to 4 bytes of MEGA_ASM_BYTES_BUF as hex into the line
        ld      de,(MEGA_DISASM_INSTR_START)                   ;#5773: ED 5B 60 EC
        ld      b,4                                            ;#5777: 06 04
ASM_LIST_FMT_DUMP4_BYTE:
        ; Emit up to 4 instr bytes of MEGA_ASM_BYTES_BUF as hex
        call    ASM_CHECK_INSTR_END                            ;#5779: CD AA 57
        jr      z,ASM_LIST_EMIT_FLAGS                          ;#577C: 28 12
        ld      a,(iy)                                         ;#577E: FD 7E 00
        inc     iy                                             ;#5781: FD 23
        call    STORE_HEX_A_AT_HL                              ;#5783: CD 41 56
        inc     de                                             ;#5786: 13
        djnz    ASM_LIST_FMT_DUMP4_BYTE                        ;#5787: 10 F0
        ld      (MEGA_DISASM_INSTR_START),de                   ;#5789: ED 53 60 EC
        call    ASM_CHECK_INSTR_END                            ;#578D: CD AA 57
ASM_LIST_EMIT_FLAGS:
        ; Emit listing-flag glyphs: LDI from ASM_LISTING_FLAG_CHARS per set LINE_FLAG bit
        ld      a,(MEGA_ASM_LINE_FLAG)                         ;#5790: 3A F7 F9
        or      a                                              ;#5793: B7
        ret     z                                              ;#5794: C8
        ld      de,MEGA_DISASM_MNEMONIC_COL                    ;#5795: 11 C9 EC
        ld      hl,ASM_LISTING_FLAG_CHARS                      ;#5798: 21 B2 57
        ld      b,6                                            ;#579B: 06 06
        rlca                                                   ;#579D: 07
        rlca                                                   ;#579E: 07
ASM_LIST_EMIT_FLAGS_BIT:
        ; Per-flag rlca + emit glyph from ASM_LISTING_FLAG_CHARS
        rlca                                                   ;#579F: 07
        jr      nc,ASM_LIST_FLAG_NEXT                          ;#57A0: 30 04
        ldi                                                    ;#57A2: ED A0
        inc     bc                                             ;#57A4: 03
        dec     hl                                             ;#57A5: 2B
ASM_LIST_FLAG_NEXT:
        ; Per-bit emit done — advance HL through ASM_LISTING_FLAG_CHARS table
        inc     hl                                             ;#57A6: 23
        djnz    ASM_LIST_EMIT_FLAGS_BIT                        ;#57A7: 10 F6
        ret                                                    ;#57A9: C9

ASM_CHECK_INSTR_END:
        ; Compute (MEGA_DISASM_CURSOR low byte - E); Z = end of instruction reached
        ld      a,(MEGA_DISASM_CURSOR)                         ;#57AA: 3A 5E EC
        sub     e                                              ;#57AD: 93
        ld      (MEGA_ASM_OP_SIGN),a                           ;#57AE: 32 56 EC
        ret                                                    ;#57B1: C9

ASM_LISTING_FLAG_CHARS:
        ; 6-byte flag-character bank "FOQDUM" — bits 5..0 of MEGA_ASM_LINE_FLAG pick chars
        ; Format: FORMAT_RAW_STRING
        ; - For embedded text that isn't 0-terminated or bit-7-terminated.
        db      "FOQDUM"                                       ;#57B2: 46 4F 51 44 55 4D

ASM_EMIT_DISPATCH_TABLE:
        ; 24 word-pointers indexed by MEGA_DISASM_OPCODE — picks the operand-emit handler
        dw      ASM_EMIT_OP_PLAIN                              ;#57B8: DB 58
        dw      ASM_EMIT_OP_ED                                 ;#57BA: E1 58
        dw      ASM_EMIT_OP_ARITH_A                            ;#57BC: E7 58
        dw      ASM_EMIT_OP_INC_DEC                            ;#57BE: FF 58
        dw      ASM_EMIT_OP_BIT                                ;#57C0: 1E 59
        dw      ASM_EMIT_OP_SHIFT                              ;#57C2: 35 59
        dw      ASM_EMIT_OP_ADC_SBC                            ;#57C4: 4F 59
        dw      ASM_EMIT_OP_ADD                                ;#57C6: 6C 59
        dw      ASM_EMIT_OP_LD                                 ;#57C8: 8D 59
        dw      ASM_EMIT_OP_CALL                               ;#57CA: 25 5A
        dw      ASM_EMIT_OP_JP                                 ;#57CC: 33 5A
        dw      ASM_EMIT_OP_JR                                 ;#57CE: 53 5A
        dw      ASM_EMIT_OP_DJNZ                               ;#57D0: 65 5A
        dw      ASM_EMIT_OP_RET                                ;#57D2: 47 5A
        dw      ASM_EMIT_OP_EX                                 ;#57D4: AA 5A
        dw      ASM_EMIT_OP_IM                                 ;#57D6: CC 5A
        dw      ASM_EMIT_OP_IN                                 ;#57D8: EB 5A
        dw      ASM_EMIT_OP_OUT                                ;#57DA: EA 5A
        dw      ASM_EMIT_OP_PUSH_POP                           ;#57DC: 0F 5B
        dw      ASM_EMIT_OP_RST                                ;#57DE: 1A 5B
        dw      ASM_EMIT_OP_ORG                                ;#57E0: 30 5B
        dw      ASM_EMIT_OP_END                                ;#57E2: 3D 5B
        dw      ASM_EMIT_OP_DEFS                               ;#57E4: 46 5B
        dw      ASM_EMIT_OP_EQU                                ;#57E6: 57 5B

ASM_PARSE_DB_DW_OPERAND:
        ; Parse a single db/dw operand — expression into EC51 or string literal (C bit 7)
        call    ASM_CLEAR_OPERAND_CELLS                        ;#57E8: CD 36 58
        bit     7,c                                            ;#57EB: CB 79
        jr      nz,ASM_PARSE_DB_DW_CHAR1                       ;#57ED: 20 18
        call    SKIP_SPACES_RAW                                ;#57EF: CD 0E 5C
        cp      "'"                                            ;#57F2: FE 27
        jr      z,ASM_PARSE_DB_DW_STRING                       ;#57F4: 28 06
        push    bc                                             ;#57F6: C5
        call    ASM_PARSE_EXPRESSION                           ;#57F7: CD DD 5D
        pop     bc                                             ;#57FA: C1
        ret                                                    ;#57FB: C9

ASM_PARSE_DB_DW_STRING:
        ; String-literal arm — clear DE, set C bit 7, fall into 1st-char loop
        ld      de,0                                           ;#57FC: 11 00 00
        set     7,c                                            ;#57FF: CB F9
        inc     hl                                             ;#5801: 23
        call    STRING_LIT_END_CHECK                           ;#5802: CD 25 58
        jr      nc,ASM_DB_DW_STRING_DONE                       ;#5805: 30 11
ASM_PARSE_DB_DW_CHAR1:
        ; Read first char of string into E (then optionally second into D)
        ld      e,(hl)                                         ;#5807: 5E
        inc     hl                                             ;#5808: 23
        bit     0,c                                            ;#5809: CB 41
        jr      nz,ASM_PARSE_DB_DW_CHAR3                       ;#580B: 20 08
        call    STRING_LIT_END_CHECK                           ;#580D: CD 25 58
        jr      nc,ASM_DB_DW_STRING_DONE                       ;#5810: 30 06
        ld      d,e                                            ;#5812: 53
        ld      e,(hl)                                         ;#5813: 5E
        inc     hl                                             ;#5814: 23
ASM_PARSE_DB_DW_CHAR3:
        ; After 3rd char — verify still within string (else syntax error)
        call    STRING_LIT_END_CHECK                           ;#5815: CD 25 58
ASM_DB_DW_STRING_DONE:
        ; End-of-string-literal arm: store accumulator into MEGA_ASM_OPERAND_VAL, ret c
        ld      (MEGA_ASM_OPERAND_VAL),de                      ;#5818: ED 53 51 EC
        ret     c                                              ;#581C: D8
        res     7,c                                            ;#581D: CB B9
        push    bc                                             ;#581F: C5
        call    ASM_EXPR_NEXT_TERM                             ;#5820: CD F3 5D
        pop     bc                                             ;#5823: C1
        ret                                                    ;#5824: C9

STRING_LIT_END_CHECK:
        ; Tests next char (HL): NUL or `'` followed by non-`'` ⇒ end of string literal
        ld      a,(hl)                                         ;#5825: 7E
        or      a                                              ;#5826: B7
        ret     z                                              ;#5827: C8
        cp      "'"                                            ;#5828: FE 27
        jr      nz,STRING_LIT_END_FOUND                        ;#582A: 20 08
        inc     hl                                             ;#582C: 23
        ld      a,(hl)                                         ;#582D: 7E
        cp      "'"                                            ;#582E: FE 27
        jr      z,STRING_LIT_END_FOUND                         ;#5830: 28 02
        or      a                                              ;#5832: B7
        ret                                                    ;#5833: C9

STRING_LIT_END_FOUND:
        ; String terminator confirmed — scf and ret (caller sees CF=1)
        scf                                                    ;#5834: 37
        ret                                                    ;#5835: C9

ASM_CLEAR_OPERAND_CELLS:
        ; Zero EC51/EC52/EC56 — reset operand-value scratch before parsing next operand
        xor     a                                              ;#5836: AF
        ld      (MEGA_ASM_OPERAND_VAL),a                       ;#5837: 32 51 EC
        ld      (MEGA_ASM_OPERAND_VAL_HI),a                    ;#583A: 32 52 EC
        ld      (MEGA_ASM_OP_SIGN),a                           ;#583D: 32 56 EC
        ret                                                    ;#5840: C9

ASM_EMIT_OPC_IXY:
        ; Emit DD/FD prefix if EC55 bit 2 set (bit 1 picks DD vs FD), then opcode in B
        ld      a,(MEGA_ASM_OPC_FLAGS)                         ;#5841: 3A 55 EC
        ld      c,a                                            ;#5844: 4F
        bit     2,c                                            ;#5845: CB 51
        jr      z,ASM_EMIT_OPCODE                              ;#5847: 28 0B
        bit     1,c                                            ;#5849: CB 49
        ld      a,Z80_DD_PREFIX                                ;#584B: 3E DD
        jr      z,ASM_EMIT_PREFIX_TAIL                         ;#584D: 28 02
        ld      a,Z80_FD_PREFIX                                ;#584F: 3E FD
ASM_EMIT_PREFIX_TAIL:
        ; IXY prefix tail — falls into ASM_EMIT_OPCODE after DD/FD emit
        call    ASM_EMIT_BYTE                                  ;#5851: CD 91 58
ASM_EMIT_OPCODE:
        ; Emit B via ASM_EMIT_BYTE; reset EC54 — the "naked opcode" emitter
        ld      a,b                                            ;#5854: 78
        call    ASM_EMIT_BYTE                                  ;#5855: CD 91 58
ASM_EMIT_OPCODE_TAIL:
        ; Cleanup tail of ASM_EMIT_OPCODE: clear MEGA_ASM_OPERAND_FLAG, ret
        push    af                                             ;#5858: F5
        xor     a                                              ;#5859: AF
        ld      (MEGA_ASM_OPERAND_FLAG),a                      ;#585A: 32 54 EC
        pop     af                                             ;#585D: F1
        ret                                                    ;#585E: C9

ASM_EMIT_OPC_8BIT:
        ; Emit opcode B then 8-bit operand (EC51) — `op nn` encoder
        call    ASM_EMIT_OPCODE                                ;#585F: CD 54 58
        jr      ASM_EMIT_EC51                                  ;#5862: 18 13

ASM_EMIT_OPC_16BIT:
        ; Emit opcode B then 16-bit operand (EC51, EC52) — `op nnnn` encoder
        call    ASM_EMIT_OPCODE                                ;#5864: CD 54 58
        jr      ASM_EMIT_OP_16BIT_TAIL                         ;#5867: 18 22

ASM_EMIT_IXY_DISP:
        ; If EC55 bit 2 set, emit IXY displacement byte (EC53); else no-op
        call    ASM_EMIT_OPC_IXY                               ;#5869: CD 41 58
        bit     2,c                                            ;#586C: CB 51
        ret     z                                              ;#586E: C8
        ld      a,(MEGA_ASM_IXY_DISP)                          ;#586F: 3A 53 EC
        jr      ASM_EMIT_BYTE                                  ;#5872: 18 1D

ASM_EMIT_IXY_OPC_8BIT:
        ; Combo: emit IXY displacement (if any), then opcode B, then EC51
        call    ASM_EMIT_IXY_DISP                              ;#5874: CD 69 58
ASM_EMIT_EC51:
        ; Emit low byte of (EC51) via ASM_EMIT_BYTE — common operand-byte tail
        ld      a,(MEGA_ASM_OPERAND_VAL)                       ;#5877: 3A 51 EC
        jr      ASM_EMIT_BYTE                                  ;#587A: 18 15

ASM_EMIT_IXY_OPC_16BIT:
        ; Combo: DD/FD prefix, opcode B, then 16-bit operand (EC51/EC52)
        call    ASM_EMIT_OPC_IXY                               ;#587C: CD 41 58
        jr      ASM_EMIT_OP_16BIT_TAIL                         ;#587F: 18 0A

ASM_EMIT_ED_OPCODE:
        ; Emit `ED` (ED prefix) then opcode in B
        ld      a,Z80_ED_PREFIX                                ;#5881: 3E ED
        call    ASM_EMIT_BYTE                                  ;#5883: CD 91 58
        jr      ASM_EMIT_OPCODE                                ;#5886: 18 CC

ASM_EMIT_ED_16BIT:
        ; Emit `ED` prefix, opcode B, then 16-bit operand (EC51/EC52)
        call    ASM_EMIT_ED_OPCODE                             ;#5888: CD 81 58
ASM_EMIT_OP_16BIT_TAIL:
        ; Common 16-bit-operand tail: emit EC51 (low) then EC52 (high) via ASM_EMIT_BYTE
        call    ASM_EMIT_EC51                                  ;#588B: CD 77 58
ASM_EMIT_OP_16BIT_HI:
        ; Load high byte (EC52) into A
        ld      a,(MEGA_ASM_OPERAND_VAL_HI)                    ;#588E: 3A 52 EC
ASM_EMIT_BYTE:
        ; Assembler byte emitter: store A at MEGA_DISASM_CURSOR (PASS-2 gated), advance iy
        exx                                                    ;#5891: D9
        ld      hl,(MEGA_DISASM_CURSOR)                        ;#5892: 2A 5E EC
        bit     0,(ix+1)                                       ;#5895: DD CB 01 46
        jr      z,ASM_EMIT_BYTE_LIST                           ;#5899: 28 20
        bit     2,(ix)                                         ;#589B: DD CB 00 56
        jr      z,ASM_EMIT_BYTE_LIST                           ;#589F: 28 1A
        push    hl                                             ;#58A1: E5
        ld      de,(MEGA_ASM_RELOC_OFFSET)                     ;#58A2: ED 5B F8 F9
        add     hl,de                                          ;#58A6: 19
        ex      de,hl                                          ;#58A7: EB
        ld      hl,(MEGA_USER_CODE_END)                        ;#58A8: 2A 07 EC
        or      a                                              ;#58AB: B7
        sbc     hl,de                                          ;#58AC: ED 52
        jr      nc,ASM_EMIT_BYTE_OOM                           ;#58AE: 30 16
        ld      hl,(MEGA_USER_CODE_START)                      ;#58B0: 2A 09 EC
        or      a                                              ;#58B3: B7
        sbc     hl,de                                          ;#58B4: ED 52
        jr      c,ASM_EMIT_BYTE_OOM                            ;#58B6: 38 0E
        ex      de,hl                                          ;#58B8: EB
        ld      (hl),a                                         ;#58B9: 77
        pop     hl                                             ;#58BA: E1
ASM_EMIT_BYTE_LIST:
        ; Skip-store path: bump cursor, append to listing-line iy buffer, restore EXX, ret
        inc     hl                                             ;#58BB: 23
        ld      (MEGA_DISASM_CURSOR),hl                        ;#58BC: 22 5E EC
        ld      (iy),a                                         ;#58BF: FD 77 00
        inc     iy                                             ;#58C2: FD 23
        exx                                                    ;#58C4: D9
        ret                                                    ;#58C5: C9

ASM_EMIT_BYTE_OOM:
        ; Out-of-range write: PRINT_OUT_OF_MEMORY then jp ASM_LINE_ERROR_EXIT
        call    PRINT_OUT_OF_MEMORY                            ;#58C6: CD F7 41
        jp      ASM_LINE_ERROR_EXIT                            ;#58C9: C3 37 53

PRINT_PULEI_PREFIX:
        ; Emit "Pulei:" (Portuguese "Skipped:") debug-prefix via PRINT_INLINE_STRING
        call    PRINT_INLINE_STRING                            ;#58CC: CD 8A 50
        db      "Pulei:"C                                      ;#58CF: 50 75 6C 65 69 BA
        ret                                                    ;#58D5: C9
        nop                                                    ;#58D6: 00
        nop                                                    ;#58D7: 00
        nop                                                    ;#58D8: 00
        nop                                                    ;#58D9: 00
        nop                                                    ;#58DA: 00

ASM_EMIT_OP_PLAIN:
        ; Dispatch 0: no-operand; ret-if-not-final then jp ASM_EMIT_OPCODE
        ret     nz                                             ;#58DB: C0
        or      a                                              ;#58DC: B7
        ret     nz                                             ;#58DD: C0
        jp      ASM_EMIT_OPCODE                                ;#58DE: C3 54 58

ASM_EMIT_OP_ED:
        ; Dispatch 1: ED-prefix no-operand (CPD/CPI/IND/INI/LDD/LDI/NEG/RETI/...)
        ret     nz                                             ;#58E1: C0
        or      a                                              ;#58E2: B7
        ret     nz                                             ;#58E3: C0
        jp      ASM_EMIT_ED_OPCODE                             ;#58E4: C3 81 58

ASM_EMIT_OP_ARITH_A:
        ; Dispatch 2: 8-bit A-arith with n or r operand (AND/CP/OR/SUB/XOR)
        ret     nz                                             ;#58E7: C0
ASM_EMIT_OP_ARITH_IXY:
        ; IXY-disp arm of arith dispatch — check bit 7,d for (IX+d)
        bit     7,d                                            ;#58E8: CB 7A
        jp      nz,ASM_EMIT_IXY_OPC_8BIT                       ;#58EA: C2 74 58
        bit     0,d                                            ;#58ED: CB 42
        ret     z                                              ;#58EF: C8
        ld      a,b                                            ;#58F0: 78
        and     0F8h                                           ;#58F1: E6 F8
        xor     40h                                            ;#58F3: EE 40
        ld      b,a                                            ;#58F5: 47
        call    ASM_INSERT_R_FROM_E                            ;#58F6: CD 46 59
        cp      76h                                            ;#58F9: FE 76
        ret     z                                              ;#58FB: C8
        jp      ASM_EMIT_IXY_DISP                              ;#58FC: C3 69 58

ASM_EMIT_OP_INC_DEC:
        ; Dispatch 3: INC/DEC — accepts r (8-bit) or rp (16-bit) operand
        ret     nz                                             ;#58FF: C0
        bit     0,d                                            ;#5900: CB 42
        jr      nz,ASM_INC_DEC_R                               ;#5902: 20 13
        bit     4,d                                            ;#5904: CB 62
        ret     z                                              ;#5906: C8
        bit     0,b                                            ;#5907: CB 40
        ld      b,3                                            ;#5909: 06 03
        jr      z,ASM_INC_DEC_RP                               ;#590B: 28 02
        ld      b,Z80_DEC_RP                                   ;#590D: 06 0B
ASM_INC_DEC_RP:
        ; 16-bit `inc/dec rp` arm — opcode = 03h or 0Bh ored with rp field
        ld      a,e                                            ;#590F: 7B
        and     30h                                            ;#5910: E6 30
        or      b                                              ;#5912: B0
        ld      b,a                                            ;#5913: 47
        jp      ASM_EMIT_OPC_IXY                               ;#5914: C3 41 58

ASM_INC_DEC_R:
        ; 8-bit `inc/dec r` arm — fold E bits 3-5 into opcode 04h/05h slot
        and     38h                                            ;#5917: E6 38
        or      b                                              ;#5919: B0
        ld      b,a                                            ;#591A: 47
        jp      ASM_EMIT_IXY_DISP                              ;#591B: C3 69 58

ASM_EMIT_OP_BIT:
        ; Dispatch 4: CB-prefix bit ops (BIT/RES/SET b,r)
        bit     7,d                                            ;#591E: CB 7A
        ret     z                                              ;#5920: C8
        call    ASM_CHECK_SIGNED_BYTE                          ;#5921: CD 83 5A
        call    nz,ASM_ERROR_SET_BIT4                          ;#5924: C4 A9 5B
        cp      8                                              ;#5927: FE 08
        call    nc,ASM_ERROR_SET_BIT4                          ;#5929: D4 A9 5B
        and     7                                              ;#592C: E6 07
        rlca                                                   ;#592E: 07
        rlca                                                   ;#592F: 07
        rlca                                                   ;#5930: 07
        or      b                                              ;#5931: B0
        ld      b,a                                            ;#5932: 47
        ex      de,hl                                          ;#5933: EB
        OVERLAP_CP                                             ;#5934: FE
ASM_EMIT_OP_SHIFT:
        ; Dispatch 5: CB-prefix shift/rotate (RL/RLC/RR/RRC/SLA/SRA/SRL r)
        ret     nz                                             ;#5935: C0
        bit     0,d                                            ;#5936: CB 42
        ret     z                                              ;#5938: C8
        call    ASM_INSERT_R_FROM_E                            ;#5939: CD 46 59
        push    bc                                             ;#593C: C5
        ld      b,Z80_CB_PREFIX                                ;#593D: 06 CB
        call    ASM_EMIT_IXY_DISP                              ;#593F: CD 69 58
        pop     bc                                             ;#5942: C1
        jp      ASM_EMIT_OPCODE                                ;#5943: C3 54 58

ASM_INSERT_R_FROM_E:
        ; Pack bits 3-5 of E into bits 0-2 of B (Z80 r-field repositioning helper)
        ld      a,e                                            ;#5946: 7B
        and     38h                                            ;#5947: E6 38
        rrca                                                   ;#5949: 0F
        rrca                                                   ;#594A: 0F
        rrca                                                   ;#594B: 0F
        or      b                                              ;#594C: B0
        ld      b,a                                            ;#594D: 47
        ret                                                    ;#594E: C9

ASM_EMIT_OP_ADC_SBC:
        ; Dispatch 6: ADC/SBC — 8-bit A,n/A,r and 16-bit HL,rp forms (ED prefix for HL)
        cp      ID_ARGUMENT_HL                                 ;#594F: FE E0
        jr      z,ASM_ADC_SBC_HL_RP                            ;#5951: 28 06
        cp      ID_ARGUMENT_A                                  ;#5953: FE B8
        ret     nz                                             ;#5955: C0
ASM_ADC_SBC_8BIT:
        ; ADC/SBC 8-bit-form arm: ex de,hl; jr into ARITH_A's body (treats as A,n/A,r)
        ex      de,hl                                          ;#5956: EB
        jr      ASM_EMIT_OP_ARITH_IXY                          ;#5957: 18 8F

ASM_ADC_SBC_HL_RP:
        ; ADC/SBC HL,rp arm — bits of B/L encode the rp pair, emit via ED prefix
        bit     1,h                                            ;#5959: CB 4C
        ret     z                                              ;#595B: C8
        ld      a,b                                            ;#595C: 78
        cpl                                                    ;#595D: 2F
        and     10h                                            ;#595E: E6 10
        rrca                                                   ;#5960: 0F
        or      42h                                            ;#5961: F6 42
        ld      b,a                                            ;#5963: 47
        ld      a,l                                            ;#5964: 7D
        and     30h                                            ;#5965: E6 30
        or      b                                              ;#5967: B0
        ld      b,a                                            ;#5968: 47
        jp      ASM_EMIT_ED_OPCODE                             ;#5969: C3 81 58

ASM_EMIT_OP_ADD:
        ; Dispatch 7: ADD — A,n / A,r / HL,rp / IX,rp / IY,rp (most varied)
        cp      ID_ARGUMENT_A                                  ;#596C: FE B8
        jr      z,ASM_ADC_SBC_8BIT                             ;#596E: 28 E6
        cp      ID_ARGUMENT_HL                                 ;#5970: FE E0
        jr      z,ASM_ADD_RP_SHIFT3                            ;#5972: 28 0B
        cp      ID_ARGUMENT_IX                                 ;#5974: FE E4
        jr      z,ASM_ADD_RP_SHIFT2                            ;#5976: 28 05
        cp      ID_ARGUMENT_IY                                 ;#5978: FE E6
        ret     nz                                             ;#597A: C0
        rr      h                                              ;#597B: CB 1C
ASM_ADD_RP_SHIFT2:
        ; ADD rp arm — second rr h shift (right-shifts H twice total before mask)
        rr      h                                              ;#597D: CB 1C
ASM_ADD_RP_SHIFT3:
        ; ADD rp arm — third rr h shift (continues shifting rp index into carry)
        rr      h                                              ;#597F: CB 1C
        rr      h                                              ;#5981: CB 1C
        ret     nc                                             ;#5983: D0
        ld      a,l                                            ;#5984: 7D
        and     30h                                            ;#5985: E6 30
        or      9                                              ;#5987: F6 09
        ld      b,a                                            ;#5989: 47
        jp      ASM_EMIT_OPC_IXY                               ;#598A: C3 41 58

ASM_EMIT_OP_LD:
        ; Dispatch 8: LD — the entire LD family (r,r' / r,n / rp,nn / (nn),r / etc.)
        ld      a,d                                            ;#598D: 7A
        and     11h                                            ;#598E: E6 11
        ld      c,0                                            ;#5990: 0E 00
        jr      nz,ASM_LD_RP_PATH                              ;#5992: 20 06
        ld      a,e                                            ;#5994: 7B
        cp      ID_ARGUMENT_LITERAL                            ;#5995: FE 30
        ret     z                                              ;#5997: C8
        inc     c                                              ;#5998: 0C
        ex      de,hl                                          ;#5999: EB
ASM_LD_RP_PATH:
        ; 16-bit LD path arm — bit-0-of-D set (rp dest); branch by L (operand category)
        bit     0,d                                            ;#599A: CB 42
        jr      z,ASM_LD_R_PATH                                ;#599C: 28 45
        ld      a,h                                            ;#599E: 7C
        and     81h                                            ;#599F: E6 81
        jr      z,ASM_LD_RP_DISPATCH                           ;#59A1: 28 08
        ld      a,e                                            ;#59A3: 7B
        and     38h                                            ;#59A4: E6 38
        or      6                                              ;#59A6: F6 06
        ld      b,a                                            ;#59A8: 47
        jr      ASM_ADC_SBC_8BIT                               ;#59A9: 18 AB

ASM_LD_RP_DISPATCH:
        ; Branch on L (operand category): 10h=I, 20h=R, 31h=A/(nn), C1h=(BC), D1h=(DE)
        ld      a,e                                            ;#59AB: 7B
        cp      ID_ARGUMENT_A                                  ;#59AC: FE B8
        ret     nz                                             ;#59AE: C0
        ld      a,l                                            ;#59AF: 7D
        cp      ID_ARGUMENT_I                                  ;#59B0: FE 10
        jr      z,ASM_LD_A_I_FAMILY                            ;#59B2: 28 22
        cp      ID_ARGUMENT_R                                  ;#59B4: FE 20
        jr      z,ASM_LD_A_R_FAMILY                            ;#59B6: 28 21
        cp      ID_ARGUMENT_LITERAL+1                          ;#59B8: FE 31
        jr      z,ASM_LD_PAREN_NN_A                            ;#59BA: 28 12
        cp      ID_ARGUMENT_BC+1                               ;#59BC: FE C1
        jr      z,ASM_LD_A_PAREN_BC_FAMILY                     ;#59BE: 28 06
        cp      ID_ARGUMENT_DE+1                               ;#59C0: FE D1
        ret     nz                                             ;#59C2: C0
        ld      b,Z80_LD_A_PAREN_DE                            ;#59C3: 06 1A
        OVERLAP_LD_DE                                          ;#59C5: 11
ASM_LD_A_PAREN_BC_FAMILY:
        ; `ld a,(bc)` / `ld (bc),a` arm (C1h tag) — Z80_LD_A_PAREN_BC (0Ah) base
        ld      b,Z80_LD_A_PAREN_BC                            ;#59C6: 06 0A
        call    ASM_OPCODE_DIR_BIT                             ;#59C8: CD 1F 5A
        jp      ASM_EMIT_OPCODE                                ;#59CB: C3 54 58

ASM_LD_PAREN_NN_A:
        ; `ld a,(nn)` / `ld (nn),a` arm (31h tag) — Z80_LD_A_PAREN_NN (3Ah) base
        ld      b,Z80_LD_A_PAREN_NN                            ;#59CE: 06 3A
        call    ASM_OPCODE_DIR_BIT                             ;#59D0: CD 1F 5A
        jp      ASM_EMIT_OPC_16BIT                             ;#59D3: C3 64 58

ASM_LD_A_I_FAMILY:
        ; `ld a,i` / `ld i,a` arm (10h tag) — ED-prefix base 57h, res 4 toggles to 47h
        ld      b,Z80_LD_A_IR_BASE                             ;#59D6: 06 57
        OVERLAP_LD_DE                                          ;#59D8: 11
ASM_LD_A_R_FAMILY:
        ; `ld a,r` / `ld r,a` arm (20h tag) — ED-prefix base 5Fh, res 4 toggles to 4Fh
        ld      b,Z80_LD_A_R                                   ;#59D9: 06 5F
        dec     c                                              ;#59DB: 0D
        jr      nz,ASM_LD_PAREN_NN_EMIT                        ;#59DC: 20 02
        res     4,b                                            ;#59DE: CB A0
ASM_LD_PAREN_NN_EMIT:
        ; Direction-bit applied — jp ASM_EMIT_ED_OPCODE to commit
        jp      ASM_EMIT_ED_OPCODE                             ;#59E0: C3 81 58

ASM_LD_R_PATH:
        ; 8-bit LD path arm — bit-4-of-D set (r dest); branch by L (operand category)
        bit     4,d                                            ;#59E3: CB 62
        ret     z                                              ;#59E5: C8
        ld      a,l                                            ;#59E6: 7D
        cp      ID_ARGUMENT_LITERAL+1                          ;#59E7: FE 31
        jr      z,ASM_LD_RP_PAREN_NN                           ;#59E9: 28 1A
        cp      ID_ARGUMENT_LITERAL                            ;#59EB: FE 30
        jr      nz,ASM_LD_SP_IXY                               ;#59ED: 20 08
        ld      a,e                                            ;#59EF: 7B
        and     30h                                            ;#59F0: E6 30
        inc     a                                              ;#59F2: 3C
        ld      b,a                                            ;#59F3: 47
        jp      ASM_EMIT_IXY_OPC_16BIT                         ;#59F4: C3 7C 58

ASM_LD_SP_IXY:
        ; `ld sp,ix/iy` arm — verify operand E=F0h, emit F9h via EMIT_OPC_IXY
        and     0F9h                                           ;#59F7: E6 F9
        cp      ID_ARGUMENT_HL                                 ;#59F9: FE E0
        ret     nz                                             ;#59FB: C0
        ld      a,e                                            ;#59FC: 7B
        cp      ID_ARGUMENT_SP                                 ;#59FD: FE F0
        ret     nz                                             ;#59FF: C0
        ld      b,Z80_LD_SP_HL                                 ;#5A00: 06 F9
        jp      ASM_EMIT_OPC_IXY                               ;#5A02: C3 41 58

ASM_LD_RP_PAREN_NN:
        ; `ld rp,(nn)` arm — emit ED-prefix 4Bh/5Bh/etc + 16-bit address
        ld      a,e                                            ;#5A05: 7B
        and     0F9h                                           ;#5A06: E6 F9
        cp      ID_ARGUMENT_HL                                 ;#5A08: FE E0
        jr      z,ASM_LD_IXY_PAREN_NN                          ;#5A0A: 28 0B
        and     30h                                            ;#5A0C: E6 30
        or      4Bh                                            ;#5A0E: F6 4B
        ld      b,a                                            ;#5A10: 47
        call    ASM_OPCODE_DIR_BIT                             ;#5A11: CD 1F 5A
        jp      ASM_EMIT_ED_16BIT                              ;#5A14: C3 88 58

ASM_LD_IXY_PAREN_NN:
        ; `ld ix,(nn)` / `ld iy,(nn)` arm — DD/FD prefix + 2Ah base + 16-bit addr
        ld      b,Z80_LD_HL_PAREN_NN                           ;#5A17: 06 2A
        call    ASM_OPCODE_DIR_BIT                             ;#5A19: CD 1F 5A
        jp      ASM_EMIT_IXY_OPC_16BIT                         ;#5A1C: C3 7C 58

ASM_OPCODE_DIR_BIT:
        ; If C ≠ 0 clear bit 3 of B (toggle load direction `(nn)←rr` vs `rr←(nn)`)
        inc     c                                              ;#5A1F: 0C
        dec     c                                              ;#5A20: 0D
        ret     z                                              ;#5A21: C8
        res     3,b                                            ;#5A22: CB 98
        ret                                                    ;#5A24: C9

ASM_EMIT_OP_CALL:
        ; Dispatch 9: CALL nn / CALL cc,nn
        call    ASM_PACK_CC_BITS                               ;#5A25: CD 91 5A
        jr      nz,ASM_CALL_CHECK_NUM                          ;#5A28: 20 03
        inc     l                                              ;#5A2A: 2C
        dec     l                                              ;#5A2B: 2D
        ret     nz                                             ;#5A2C: C0
ASM_CALL_CHECK_NUM:
        ; CALL nn arm — verify operand is numeric (L = '0' marker), emit 16-bit
        cp      ID_ARGUMENT_LITERAL                            ;#5A2D: FE 30
        ret     nz                                             ;#5A2F: C0
        jp      ASM_EMIT_OPC_16BIT                             ;#5A30: C3 64 58

ASM_EMIT_OP_JP:
        ; Dispatch 10: JP nn / JP cc,nn / JP (HL) / JP (IX) / JP (IY)
        and     0F9h                                           ;#5A33: E6 F9
        cp      0B0h                                           ;#5A35: FE B0
        ld      a,e                                            ;#5A37: 7B
        jr      nz,ASM_EMIT_OP_CALL                            ;#5A38: 20 EB
        inc     l                                              ;#5A3A: 2C
        dec     l                                              ;#5A3B: 2D
        ret     nz                                             ;#5A3C: C0
        ld      a,(MEGA_ASM_IXY_DISP)                          ;#5A3D: 3A 53 EC
        or      a                                              ;#5A40: B7
        ret     nz                                             ;#5A41: C0
        ld      b,Z80_JP_HL                                    ;#5A42: 06 E9
        jp      ASM_EMIT_OPC_IXY                               ;#5A44: C3 41 58

ASM_EMIT_OP_RET:
        ; Dispatch 13: RET / RET cc
        ret     nz                                             ;#5A47: C0
        call    ASM_PACK_CC_BITS                               ;#5A48: CD 91 5A
        jr      nz,ASM_RET_CC_EMIT                             ;#5A4B: 20 03
        inc     e                                              ;#5A4D: 1C
        dec     e                                              ;#5A4E: 1D
        ret     nz                                             ;#5A4F: C0
ASM_RET_CC_EMIT:
        ; RET cc arm — operand E nonzero (cc present), emit packed opcode
        jp      ASM_EMIT_OPCODE                                ;#5A50: C3 54 58

ASM_EMIT_OP_JR:
        ; Dispatch 11: JR e / JR cc,e (relative jump with cc=NZ/Z/NC/C only)
        call    ASM_CHECK_CC_AF                                ;#5A53: CD A2 5A
        bit     6,d                                            ;#5A56: CB 72
        jr      z,ASM_EMIT_OP_DJNZ                             ;#5A58: 28 0B
        bit     5,e                                            ;#5A5A: CB 6B
        ret     nz                                             ;#5A5C: C0
        and     18h                                            ;#5A5D: E6 18
        or      20h                                            ;#5A5F: F6 20
        ld      b,a                                            ;#5A61: 47
        ld      a,l                                            ;#5A62: 7D
        jr      ASM_EMIT_REL_CHECK_ZERO                        ;#5A63: 18 03

ASM_EMIT_OP_DJNZ:
        ; Dispatch 12: DJNZ e (relative)
        inc     l                                              ;#5A65: 2C
        dec     l                                              ;#5A66: 2D
        ret     nz                                             ;#5A67: C0
ASM_EMIT_REL_CHECK_ZERO:
        ; Shared rel-jump finalize — cp '0', compute disp via OPERAND_VAL
        cp      ID_ARGUMENT_LITERAL                            ;#5A68: FE 30
        ret     nz                                             ;#5A6A: C0
        ld      hl,(MEGA_ASM_OPERAND_VAL)                      ;#5A6B: 2A 51 EC
        dec     hl                                             ;#5A6E: 2B
        dec     hl                                             ;#5A6F: 2B
        ld      de,(MEGA_DISASM_INSTR_START)                   ;#5A70: ED 5B 60 EC
        or      a                                              ;#5A74: B7
        sbc     hl,de                                          ;#5A75: ED 52
        ld      (MEGA_ASM_OPERAND_VAL),hl                      ;#5A77: 22 51 EC
        call    ASM_CHECK_SIGNED_BYTE                          ;#5A7A: CD 83 5A
        call    nz,ASM_ERROR_SET_BIT2                          ;#5A7D: C4 A3 5B
        jp      ASM_EMIT_OPC_8BIT                              ;#5A80: C3 5F 58

ASM_CHECK_SIGNED_BYTE:
        ; Sign-extend (EC51) into 16 bits; Z=1 if fits in signed byte (-128..127), A=L
        push    hl                                             ;#5A83: E5
        ld      hl,(MEGA_ASM_OPERAND_VAL)                      ;#5A84: 2A 51 EC
        bit     7,l                                            ;#5A87: CB 7D
        jr      z,ASM_CHECK_SBYTE_HIGH                         ;#5A89: 28 01
        inc     h                                              ;#5A8B: 24
ASM_CHECK_SBYTE_HIGH:
        ; High-byte fixup arm — inc h then dec h to set Z if H==0 after sign-extend
        inc     h                                              ;#5A8C: 24
        dec     h                                              ;#5A8D: 25
        ld      a,l                                            ;#5A8E: 7D
        pop     hl                                             ;#5A8F: E1
        ret                                                    ;#5A90: C9

ASM_PACK_CC_BITS:
        ; cc-bit packer: call CHECK_CC_AF, fold cc bits 3-5 from E into opcode B
        call    ASM_CHECK_CC_AF                                ;#5A91: CD A2 5A
        bit     6,d                                            ;#5A94: CB 72
        ret     z                                              ;#5A96: C8
        ld      a,b                                            ;#5A97: 78
        and     0C6h                                           ;#5A98: E6 C6
        ld      b,a                                            ;#5A9A: 47
        ld      a,e                                            ;#5A9B: 7B
        and     38h                                            ;#5A9C: E6 38
        or      b                                              ;#5A9E: B0
        ld      b,a                                            ;#5A9F: 47
        ld      a,l                                            ;#5AA0: 7D
        ret                                                    ;#5AA1: C9

ASM_CHECK_CC_AF:
        ; Test for AF marker (88h): if so, load DE=4058h (special-case PUSH AF encoding)
        cp      ID_ARGUMENT_C                                  ;#5AA2: FE 88
        ret     nz                                             ;#5AA4: C0
        ld      de,4058h                                       ;#5AA5: 11 58 40
        ld      a,e                                            ;#5AA8: 7B
        ret                                                    ;#5AA9: C9

ASM_EMIT_OP_EX:
        ; Dispatch 14: EX DE,HL / EX AF,AF' / EX (SP),HL/IX/IY
        cp      ID_ARGUMENT_SP+1                               ;#5AAA: FE F1
        jr      z,ASM_EX_SP_HL_IXY                             ;#5AAC: 28 13
        cp      ID_ARGUMENT_AF                                 ;#5AAE: FE F8
        jr      z,ASM_EX_AF_AFP                                ;#5AB0: 28 09
        cp      ID_ARGUMENT_DE                                 ;#5AB2: FE D0
        ret     nz                                             ;#5AB4: C0
        ld      bc,0EBE0h                                      ;#5AB5: 01 E0 EB
        ld      a,l                                            ;#5AB8: 7D
        jr      ASM_EMIT_EX_FINISH                             ;#5AB9: 18 0C

ASM_EX_AF_AFP:
        ; `ex af,af'` arm — load opcode 08h via BC=08F8h, jr to FINISH
        ld      bc,8F8h                                        ;#5ABB: 01 F8 08
        ld      a,l                                            ;#5ABE: 7D
        jr      ASM_EMIT_EX_FINISH                             ;#5ABF: 18 06

ASM_EX_SP_HL_IXY:
        ; `ex (sp),hl/ix/iy` arm — opcode E3h via BC=E3E0h, optional IXY prefix
        ld      a,l                                            ;#5AC1: 7D
        and     0F9h                                           ;#5AC2: E6 F9
        ld      bc,0E3E0h                                      ;#5AC4: 01 E0 E3
ASM_EMIT_EX_FINISH:
        ; Common tail of ASM_EMIT_OP_EX: verify the picked opcode matches, jp EMIT_OPC_IXY
        cp      c                                              ;#5AC7: B9
        ret     nz                                             ;#5AC8: C0
        jp      ASM_EMIT_OPC_IXY                               ;#5AC9: C3 41 58

ASM_EMIT_OP_IM:
        ; Dispatch 15: IM 0 / IM 1 / IM 2 (ED prefix)
        ret     nz                                             ;#5ACC: C0
        bit     7,d                                            ;#5ACD: CB 7A
        ret     z                                              ;#5ACF: C8
        call    ASM_CHECK_SIGNED_BYTE                          ;#5AD0: CD 83 5A
        call    nz,ASM_ERROR_SET_BIT4                          ;#5AD3: C4 A9 5B
        inc     a                                              ;#5AD6: 3C
        ld      b,Z80_IM_0_OPC                                 ;#5AD7: 06 46
        dec     a                                              ;#5AD9: 3D
        jr      z,ASM_EMIT_IM_OPCODE                           ;#5ADA: 28 0B
        dec     a                                              ;#5ADC: 3D
        ld      b,Z80_IM_1_OPC                                 ;#5ADD: 06 56
        jr      z,ASM_EMIT_IM_OPCODE                           ;#5ADF: 28 06
        dec     a                                              ;#5AE1: 3D
        ld      b,Z80_IM_2_OPC                                 ;#5AE2: 06 5E
        call    nz,ASM_ERROR_SET_BIT4                          ;#5AE4: C4 A9 5B
ASM_EMIT_IM_OPCODE:
        ; IM 0/1/2 tail — jp ASM_EMIT_ED_OPCODE; reached after B = 46h/56h/5Eh set
        jp      ASM_EMIT_ED_OPCODE                             ;#5AE7: C3 81 58

ASM_EMIT_OP_OUT:
        ; Dispatch 17: OUT (n),A / OUT (C),r — `ex de,hl` then falls into IN's logic
        ex      de,hl                                          ;#5AEA: EB
ASM_EMIT_OP_IN:
        ; Dispatch 16: IN A,(n) / IN r,(C) — shared body with OUT
        ld      a,l                                            ;#5AEB: 7D
        cp      ID_ARGUMENT_LITERAL+1                          ;#5AEC: FE 31
        jr      nz,ASM_IN_OUT_C_R                              ;#5AEE: 20 07
        ld      a,e                                            ;#5AF0: 7B
        cp      ID_ARGUMENT_A                                  ;#5AF1: FE B8
        ret     nz                                             ;#5AF3: C0
        jp      ASM_EMIT_OPC_8BIT                              ;#5AF4: C3 5F 58

ASM_IN_OUT_C_R:
        ; `(c),r` / `r,(c)` arm — ED-prefix encoding with r-field from E
        cp      ID_ARGUMENT_C+1                                ;#5AF7: FE 89
        ret     nz                                             ;#5AF9: C0
        bit     0,d                                            ;#5AFA: CB 42
        ret     z                                              ;#5AFC: C8
        ld      a,e                                            ;#5AFD: 7B
        and     38h                                            ;#5AFE: E6 38
        cp      30h                                            ;#5B00: FE 30
        ret     z                                              ;#5B02: C8
        bit     3,b                                            ;#5B03: CB 58
        ld      b,Z80_IN_R_C_BASE                              ;#5B05: 06 40
        jr      nz,ASM_IN_OUT_C_R_DIR                          ;#5B07: 20 01
        inc     b                                              ;#5B09: 04
ASM_IN_OUT_C_R_DIR:
        ; Direction-bit packer for the C-form: OR carry-derived 40h/41h with B
        or      b                                              ;#5B0A: B0
        ld      b,a                                            ;#5B0B: 47
        jp      ASM_EMIT_ED_OPCODE                             ;#5B0C: C3 81 58

ASM_EMIT_OP_PUSH_POP:
        ; Dispatch 18: PUSH rp / POP rp
        ret     nz                                             ;#5B0F: C0
        bit     5,d                                            ;#5B10: CB 6A
        ret     z                                              ;#5B12: C8
        and     30h                                            ;#5B13: E6 30
        or      b                                              ;#5B15: B0
        ld      b,a                                            ;#5B16: 47
        jp      ASM_EMIT_OPC_IXY                               ;#5B17: C3 41 58

ASM_EMIT_OP_RST:
        ; Dispatch 19: RST p (p ∈ {0,8,10h,18h,20h,28h,30h,38h})
        ret     nz                                             ;#5B1A: C0
        cp      ID_ARGUMENT_LITERAL                            ;#5B1B: FE 30
        ret     nz                                             ;#5B1D: C0
        call    ASM_CHECK_SIGNED_BYTE                          ;#5B1E: CD 83 5A
        call    nz,ASM_ERROR_SET_BIT4                          ;#5B21: C4 A9 5B
        ld      c,a                                            ;#5B24: 4F
        and     38h                                            ;#5B25: E6 38
        cp      c                                              ;#5B27: B9
        call    nz,ASM_ERROR_SET_BIT4                          ;#5B28: C4 A9 5B
        or      b                                              ;#5B2B: B0
        ld      b,a                                            ;#5B2C: 47
        jp      ASM_EMIT_OPCODE                                ;#5B2D: C3 54 58

ASM_EMIT_OP_ORG:
        ; Dispatch 20: `ORG nnnn` pseudo-op — set assembly origin
        ret     nz                                             ;#5B30: C0
        cp      ID_ARGUMENT_LITERAL                            ;#5B31: FE 30
        ret     nz                                             ;#5B33: C0
        ld      hl,(MEGA_ASM_OPERAND_VAL)                      ;#5B34: 2A 51 EC
        ld      (MEGA_DISASM_CURSOR),hl                        ;#5B37: 22 5E EC
        jp      ASM_DIRECTIVE_DONE                             ;#5B3A: C3 94 5B

ASM_EMIT_OP_END:
        ; Dispatch 21: `END` pseudo-op — mark end of source
        ret     nz                                             ;#5B3D: C0
        or      a                                              ;#5B3E: B7
        ret     nz                                             ;#5B3F: C0
        call    ASM_LIST_CURRENT_LINE                          ;#5B40: CD 65 56
        jp      ASM_LINE_WARN_EXIT                             ;#5B43: C3 3B 53

ASM_EMIT_OP_DEFS:
        ; Dispatch 22: `DEFS n` / `DS n` pseudo-op — reserve n bytes (zero-fill)
        ret     nz                                             ;#5B46: C0
        cp      ID_ARGUMENT_LITERAL                            ;#5B47: FE 30
        ret     nz                                             ;#5B49: C0
        ld      hl,(MEGA_DISASM_CURSOR)                        ;#5B4A: 2A 5E EC
        ex      de,hl                                          ;#5B4D: EB
        ld      hl,(MEGA_ASM_OPERAND_VAL)                      ;#5B4E: 2A 51 EC
        add     hl,de                                          ;#5B51: 19
        ld      (MEGA_DISASM_CURSOR),hl                        ;#5B52: 22 5E EC
        jr      ASM_DIRECTIVE_DONE                             ;#5B55: 18 3D

ASM_EMIT_OP_EQU:
        ; Dispatch 23: `LABEL EQU value` pseudo-op — define an absolute symbol
        ret     nz                                             ;#5B57: C0
        cp      ID_ARGUMENT_LITERAL                            ;#5B58: FE 30
        ret     nz                                             ;#5B5A: C0
        ld      hl,MEGA_ASM_LINE_BUF                           ;#5B5B: 21 14 ED
        call    PARSE_LABEL_NAME                               ;#5B5E: CD D9 5B
        cp      ":"                                            ;#5B61: FE 3A
        jp      nz,ASM_ERROR_RAISE                             ;#5B63: C2 BC 5B
        ld      hl,(MEGA_ASM_OPERAND_VAL)                      ;#5B66: 2A 51 EC
        ld      (MEGA_DISASM_INSTR_START),hl                   ;#5B69: 22 60 EC
        ex      de,hl                                          ;#5B6C: EB
        bit     0,(ix+1)                                       ;#5B6D: DD CB 01 46
        jr      nz,ASM_DIRECTIVE_DONE                          ;#5B71: 20 21
        ld      hl,(MEGA_SYM_VALUE_PTR)                        ;#5B73: 2A 5C EC
        ld      a,(MEGA_ASM_LINE_FLAG)                         ;#5B76: 3A F7 F9
        or      a                                              ;#5B79: B7
        jr      z,ASM_EQU_WRITE_VAL                            ;#5B7A: 28 0F
        dec     hl                                             ;#5B7C: 2B
        dec     hl                                             ;#5B7D: 2B
        call    MEGA_SLOT_READ_HL                              ;#5B7E: CD 16 FA
        set     7,a                                            ;#5B81: CB FF
        call    MEGA_SLOT_WRITE                                ;#5B83: CD 10 FA
        inc     hl                                             ;#5B86: 23
        inc     hl                                             ;#5B87: 23
        ld      de,0                                           ;#5B88: 11 00 00
ASM_EQU_WRITE_VAL:
        ; Common arm — slot-write E then D as the 2-byte value at MEGA_SYM_VALUE_PTR
        ld      a,e                                            ;#5B8B: 7B
        call    MEGA_SLOT_WRITE                                ;#5B8C: CD 10 FA
        inc     hl                                             ;#5B8F: 23
        ld      a,d                                            ;#5B90: 7A
        call    MEGA_SLOT_WRITE                                ;#5B91: CD 10 FA
ASM_DIRECTIVE_DONE:
        ; Common tail of EQU/ORG/label handlers — jp into ASM_EMIT_OPCODE's pop+ret exit
        jp      ASM_EMIT_OPCODE_TAIL                           ;#5B94: C3 58 58

ASM_ERROR_SET_BIT0:
        ; Set bit 0 of (ix+2) and jr ASM_ERROR_CLEANUP — one of four error-flag setters
        set     0,(ix+2)                                       ;#5B97: DD CB 02 C6
        jr      ASM_ERROR_CLEANUP                              ;#5B9B: 18 10

ASM_ERROR_SET_BIT1:
        ; Set bit 1 of (ix+2) and jr ASM_ERROR_CLEANUP
        set     1,(ix+2)                                       ;#5B9D: DD CB 02 CE
        jr      ASM_ERROR_CLEANUP                              ;#5BA1: 18 0A

ASM_ERROR_SET_BIT2:
        ; Set bit 2 of (ix+2) and jr ASM_ERROR_CLEANUP
        set     2,(ix+2)                                       ;#5BA3: DD CB 02 D6
        jr      ASM_ERROR_CLEANUP                              ;#5BA7: 18 04

ASM_ERROR_SET_BIT4:
        ; Set bit 4 of (ix+2) and fall into ASM_ERROR_CLEANUP
        set     4,(ix+2)                                       ;#5BA9: DD CB 02 E6
ASM_ERROR_CLEANUP:
        ; Shared tail of the error-flag setters (5B97/5B9D/5BA3/5BA9) — zero EC51, ret
        push    hl                                             ;#5BAD: E5
        ld      hl,0                                           ;#5BAE: 21 00 00
        ld      (MEGA_ASM_OPERAND_VAL),hl                      ;#5BB1: 22 51 EC
        pop     hl                                             ;#5BB4: E1
        ret                                                    ;#5BB5: C9

ASM_ERROR_NO_MNEMONIC:
        ; Set bit 3 of (ix+2): first letter not A-X, or no matching mnemonic record
        ld      a,8                                            ;#5BB6: 3E 08
        OVERLAP_LD_HL                                          ;#5BB8: 21
ASM_ERROR_OPERAND:
        ; Set bit 4 of (ix+2): operand-flag set after parse, or PARSE_HEX_NUM overflow
        ld      a,10h                                          ;#5BB9: 3E 10
        OVERLAP_LD_HL                                          ;#5BBB: 21
ASM_ERROR_RAISE:
        ; Set bit 5 of (ix+2) error flag; rewind cursor, jp 532B (generic error)
        ld      a,20h                                          ;#5BBC: 3E 20
        or      (ix+2)                                         ;#5BBE: DD B6 02
        ld      (ix+2),a                                       ;#5BC1: DD 77 02
        ld      hl,(MEGA_DISASM_INSTR_START)                   ;#5BC4: 2A 60 EC
        ld      (MEGA_DISASM_CURSOR),hl                        ;#5BC7: 22 5E EC
        ld      iy,MEGA_ASM_BYTES_BUF                          ;#5BCA: FD 21 8E EC
        ld      b,3                                            ;#5BCE: 06 03
ASM_ERROR_RAISE_ZERO_BYTE:
        ; Zero out 3 bytes of MEGA_ASM_BYTES_BUF via ASM_EMIT_BYTE
        xor     a                                              ;#5BD0: AF
        call    ASM_EMIT_BYTE                                  ;#5BD1: CD 91 58
        djnz    ASM_ERROR_RAISE_ZERO_BYTE                      ;#5BD4: 10 FA
        jp      ASM_LINE_FINALIZE                              ;#5BD6: C3 2B 53

PARSE_LABEL_NAME:
        ; Copy a label/symbol name from (HL) into MEGA_LABEL_NAME (max 6 chars; ':' ends)
        ld      b,6                                            ;#5BD9: 06 06
        ld      de,MEGA_LABEL_NAME                             ;#5BDB: 11 AF EC
        push    de                                             ;#5BDE: D5
        ld      a," "                                          ;#5BDF: 3E 20
PARSE_LABEL_NAME_PAD:
        ; Pad MEGA_LABEL_NAME with 6 spaces before copy
        ld      (de),a                                         ;#5BE1: 12
        inc     de                                             ;#5BE2: 13
        djnz    PARSE_LABEL_NAME_PAD                           ;#5BE3: 10 FC
        pop     de                                             ;#5BE5: D1
        call    SKIP_SPACES_RAW                                ;#5BE6: CD 0E 5C
        cp      "?"                                            ;#5BE9: FE 3F
        ret     c                                              ;#5BEB: D8
        cp      "Z"+1                                          ;#5BEC: FE 5B
        ret     nc                                             ;#5BEE: D0
PARSE_LABEL_STORE_CHAR:
        ; Per-char body: store at (de), advance HL, check next char's range (0-9 / A-Z)
        ld      c,a                                            ;#5BEF: 4F
        ld      a,b                                            ;#5BF0: 78
        cp      6                                              ;#5BF1: FE 06
        jr      z,PARSE_LABEL_NEXT_CHAR                        ;#5BF3: 28 04
        ld      a,c                                            ;#5BF5: 79
        ld      (de),a                                         ;#5BF6: 12
        inc     de                                             ;#5BF7: 13
        inc     b                                              ;#5BF8: 04
PARSE_LABEL_NEXT_CHAR:
        ; Advance HL, read next char — '0'/':' terminate, else fall to range-check
        inc     hl                                             ;#5BF9: 23
        ld      a,(hl)                                         ;#5BFA: 7E
        cp      "0"                                            ;#5BFB: FE 30
        ret     c                                              ;#5BFD: D8
        cp      "9"+1                                          ;#5BFE: FE 3A
        jr      nz,PARSE_LABEL_BAD_CHAR                        ;#5C00: 20 02
        inc     hl                                             ;#5C02: 23
        ret                                                    ;#5C03: C9

PARSE_LABEL_BAD_CHAR:
        ; Non-printable/extended char — fall to A-Z range check for second-and-later chars
        jr      c,PARSE_LABEL_STORE_CHAR                       ;#5C04: 38 E9
        cp      "A"                                            ;#5C06: FE 41
        ret     c                                              ;#5C08: D8
        cp      "Z"+1                                          ;#5C09: FE 5B
        ret     nc                                             ;#5C0B: D0
        jr      PARSE_LABEL_STORE_CHAR                         ;#5C0C: 18 E1

SKIP_SPACES_RAW:
        ; Variant of SKIP_SPACES: ret nz on first non-space; no zero-terminator check
        ld      a,(hl)                                         ;#5C0E: 7E
        cp      " "                                            ;#5C0F: FE 20
        ret     nz                                             ;#5C11: C0
        inc     hl                                             ;#5C12: 23
        jr      SKIP_SPACES_RAW                                ;#5C13: 18 F9

ASM_INSERT_OR_UPDATE_LABEL:
        ; PASS1: LOOKUP_LABEL then append-with-value; PASS2: validate matches
        call    LOOKUP_LABEL                                   ;#5C15: CD 03 5D
        bit     0,(ix+1)                                       ;#5C18: DD CB 01 46
        jr      nz,ASM_VALIDATE_LABEL_PASS2                    ;#5C1C: 20 46
        jr      c,ASM_LABEL_MARK_DEFINED                       ;#5C1E: 38 3A
        ld      bc,0Bh                                         ;#5C20: 01 0B 00
        push    hl                                             ;#5C23: E5
        add     hl,bc                                          ;#5C24: 09
        ld      de,(MEGA_SYM_TABLE_END)                        ;#5C25: ED 5B 4B EC
        or      a                                              ;#5C29: B7
        sbc     hl,de                                          ;#5C2A: ED 52
        pop     de                                             ;#5C2C: D1
        jr      nc,ASM_SYM_TABLE_FULL                          ;#5C2D: 30 48
        ld      c,6                                            ;#5C2F: 0E 06
        ld      hl,MEGA_LABEL_NAME                             ;#5C31: 21 AF EC
        call    MEGA_SLOT_LDIR                                 ;#5C34: CD 22 FA
        ex      de,hl                                          ;#5C37: EB
        ld      (MEGA_SYM_VALUE_PTR),hl                        ;#5C38: 22 5C EC
        ld      de,(MEGA_DISASM_CURSOR)                        ;#5C3B: ED 5B 5E EC
        ld      a,e                                            ;#5C3F: 7B
        call    MEGA_SLOT_WRITE                                ;#5C40: CD 10 FA
        inc     hl                                             ;#5C43: 23
        ld      a,d                                            ;#5C44: 7A
        call    MEGA_SLOT_WRITE                                ;#5C45: CD 10 FA
        inc     hl                                             ;#5C48: 23
        xor     a                                              ;#5C49: AF
        call    MEGA_SLOT_WRITE                                ;#5C4A: CD 10 FA
        inc     hl                                             ;#5C4D: 23
        call    MEGA_SLOT_WRITE                                ;#5C4E: CD 10 FA
        inc     hl                                             ;#5C51: 23
        call    MEGA_SLOT_WRITE                                ;#5C52: CD 10 FA
        inc     hl                                             ;#5C55: 23
        ld      (MEGA_SYM_TABLE_HEAD),hl                       ;#5C56: 22 64 EC
        ret                                                    ;#5C59: C9

ASM_LABEL_MARK_DEFINED:
        ; PASS1 with existing label: set bit 7 of value byte to mark as defined
        dec     hl                                             ;#5C5A: 2B
        call    MEGA_SLOT_READ_HL                              ;#5C5B: CD 16 FA
        set     7,a                                            ;#5C5E: CB FF
        call    MEGA_SLOT_WRITE                                ;#5C60: CD 10 FA
        ret                                                    ;#5C63: C9

ASM_VALIDATE_LABEL_PASS2:
        ; PASS2 check: walk back over the symbol record, verify the bit-7 terminators
        dec     hl                                             ;#5C64: 2B
        call    MEGA_SLOT_READ_HL                              ;#5C65: CD 16 FA
        bit     7,a                                            ;#5C68: CB 7F
        call    nz,ASM_ERROR_SET_BIT0                          ;#5C6A: C4 97 5B
        dec     hl                                             ;#5C6D: 2B
        call    MEGA_SLOT_READ_HL                              ;#5C6E: CD 16 FA
        bit     7,a                                            ;#5C71: CB 7F
        ret     z                                              ;#5C73: C8
        jp      ASM_ERROR_SET_BIT1                             ;#5C74: C3 9D 5B

ASM_SYM_TABLE_FULL:
        ; No symbol-table space: call PRINT_LABEL_TABLE_FULL, jp ASM_LINE_ERROR_EXIT
        call    PRINT_LABEL_TABLE_FULL                         ;#5C77: CD 38 42
        jp      ASM_LINE_ERROR_EXIT                            ;#5C7A: C3 37 53

PRINT_ACHEI_PREFIX:
        ; Emit "Achei:" debug-prefix via PRINT_INLINE_STRING (used by F-command)
        call    PRINT_INLINE_STRING                            ;#5C7D: CD 8A 50
        db      "Achei:"C                                      ;#5C80: 41 63 68 65 69 BA
        ret                                                    ;#5C86: C9
        nop                                                    ;#5C87: 00
        nop                                                    ;#5C88: 00

RESOLVE_LABEL_VALUE:
        ; LOOKUP_LABEL then read 2 bytes after the name into DE (the label value)
        call    LOOKUP_LABEL                                   ;#5C89: CD 03 5D
        ld      de,0                                           ;#5C8C: 11 00 00
        jp      nc,ASM_ERROR_SET_BIT1                          ;#5C8F: D2 9D 5B
        call    MEGA_SLOT_READ_HL                              ;#5C92: CD 16 FA
        ld      e,a                                            ;#5C95: 5F
        inc     hl                                             ;#5C96: 23
        call    MEGA_SLOT_READ_HL                              ;#5C97: CD 16 FA
        ld      d,a                                            ;#5C9A: 57
        ld      a,(MEGA_DISASM_OPCODE)                         ;#5C9B: 3A 57 EC
        cp      14h                                            ;#5C9E: FE 14
        jr      c,RESOLVE_LABEL_DEFERRED                       ;#5CA0: 38 0B
        cp      18h                                            ;#5CA2: FE 18
        jr      nc,RESOLVE_LABEL_DEFERRED                      ;#5CA4: 30 07
        dec     hl                                             ;#5CA6: 2B
        call    ASM_VALIDATE_LABEL_PASS2                       ;#5CA7: CD 64 5C
        inc     hl                                             ;#5CAA: 23
        inc     hl                                             ;#5CAB: 23
        inc     hl                                             ;#5CAC: 23
RESOLVE_LABEL_DEFERRED:
        ; Post-resolve: for opt_type 14h-17h record PASS2 ref, then check ix flags
        bit     4,(ix)                                         ;#5CAD: DD CB 00 66
        ret     z                                              ;#5CB1: C8
        bit     0,(ix+1)                                       ;#5CB2: DD CB 01 46
        ret     z                                              ;#5CB6: C8
        push    de                                             ;#5CB7: D5
        push    hl                                             ;#5CB8: E5
        inc     hl                                             ;#5CB9: 23
RESOLVE_LABEL_WALK_REFS:
        ; Walk the symbol's per-reference list — read next 2-byte ref pointer
        call    MEGA_SLOT_READ_HL                              ;#5CBA: CD 16 FA
        ld      e,a                                            ;#5CBD: 5F
        inc     hl                                             ;#5CBE: 23
        call    MEGA_SLOT_READ_HL                              ;#5CBF: CD 16 FA
        ld      d,a                                            ;#5CC2: 57
        or      e                                              ;#5CC3: B3
        ex      de,hl                                          ;#5CC4: EB
        jr      nz,RESOLVE_LABEL_WALK_REFS                     ;#5CC5: 20 F3
        dec     de                                             ;#5CC7: 1B
        ld      hl,(MEGA_SYM_TABLE_HEAD)                       ;#5CC8: 2A 64 EC
        push    de                                             ;#5CCB: D5
        push    hl                                             ;#5CCC: E5
        ld      de,5                                           ;#5CCD: 11 05 00
        add     hl,de                                          ;#5CD0: 19
        ld      de,(MEGA_SYM_TABLE_END)                        ;#5CD1: ED 5B 4B EC
        sbc     hl,de                                          ;#5CD5: ED 52
        pop     hl                                             ;#5CD7: E1
        pop     de                                             ;#5CD8: D1
        jr      nc,ASM_SYM_TABLE_FULL                          ;#5CD9: 30 9C
        ex      de,hl                                          ;#5CDB: EB
        ld      a,e                                            ;#5CDC: 7B
        call    MEGA_SLOT_WRITE                                ;#5CDD: CD 10 FA
        inc     hl                                             ;#5CE0: 23
        ld      a,d                                            ;#5CE1: 7A
        call    MEGA_SLOT_WRITE                                ;#5CE2: CD 10 FA
        ex      de,hl                                          ;#5CE5: EB
        xor     a                                              ;#5CE6: AF
        call    MEGA_SLOT_WRITE                                ;#5CE7: CD 10 FA
        inc     hl                                             ;#5CEA: 23
        call    MEGA_SLOT_WRITE                                ;#5CEB: CD 10 FA
        inc     hl                                             ;#5CEE: 23
        ld      de,(MEGA_DISASM_INSTR_START)                   ;#5CEF: ED 5B 60 EC
        ld      a,e                                            ;#5CF3: 7B
        call    MEGA_SLOT_WRITE                                ;#5CF4: CD 10 FA
        inc     hl                                             ;#5CF7: 23
        ld      a,d                                            ;#5CF8: 7A
        call    MEGA_SLOT_WRITE                                ;#5CF9: CD 10 FA
        inc     hl                                             ;#5CFC: 23
        ld      (MEGA_SYM_TABLE_HEAD),hl                       ;#5CFD: 22 64 EC
        pop     hl                                             ;#5D00: E1
        pop     de                                             ;#5D01: D1
        ret                                                    ;#5D02: C9

LOOKUP_LABEL:
        ; Walk the assembler symbol table at (EC49); CF=1 + HL/DE on match, CF=0 not found
        ld      hl,(MEGA_SYM_TABLE_BASE)                       ;#5D03: 2A 49 EC
        ld      b,0                                            ;#5D06: 06 00
        jr      LOOKUP_LABEL_READ                              ;#5D08: 18 04

LOOKUP_LABEL_NEXT:
        ; Per-record advance — 3× inc C plus add HL,BC to skip to next record
        inc     c                                              ;#5D0A: 0C
        inc     c                                              ;#5D0B: 0C
        inc     c                                              ;#5D0C: 0C
        add     hl,bc                                          ;#5D0D: 09
LOOKUP_LABEL_READ:
        ; Per-record head — read first name byte, EOT check, init match loop
        call    MEGA_SLOT_READ_HL                              ;#5D0E: CD 16 FA
        or      a                                              ;#5D11: B7
        jr      z,LOOKUP_LABEL_RET                             ;#5D12: 28 17
        ld      de,MEGA_LABEL_NAME                             ;#5D14: 11 AF EC
        ld      c,6                                            ;#5D17: 0E 06
LOOKUP_LABEL_MATCH_LOOP:
        ; Per-char compare of 6-byte name from MEGA_LABEL_NAME vs slot record (bit-7 mask)
        ld      a,(de)                                         ;#5D19: 1A
        push    bc                                             ;#5D1A: C5
        ld      b,a                                            ;#5D1B: 47
        call    MEGA_SLOT_READ_HL                              ;#5D1C: CD 16 FA
        xor     b                                              ;#5D1F: A8
        pop     bc                                             ;#5D20: C1
        and     7Fh                                            ;#5D21: E6 7F
        inc     hl                                             ;#5D23: 23
        inc     de                                             ;#5D24: 13
        jr      nz,LOOKUP_LABEL_NEXT                           ;#5D25: 20 E3
        dec     c                                              ;#5D27: 0D
        jr      nz,LOOKUP_LABEL_MATCH_LOOP                     ;#5D28: 20 EF
        scf                                                    ;#5D2A: 37
LOOKUP_LABEL_RET:
        ; Shared `ret` — reached with CF=1 on match (scf at 5D2A) or CF=0 on EOT
        ret                                                    ;#5D2B: C9

ASM_PARSE_OPERANDS:
        ; Parse operand 1 via ASM_PARSE_OPERAND_AND_SEP; if comma, parse operand 2 too
        call    ASM_PARSE_OPERAND_AND_SEP                      ;#5D2C: CD 6F 5D
        cp      ","                                            ;#5D2F: FE 2C
        push    bc                                             ;#5D31: C5
        jr      z,ASM_PARSE_OPERAND2                           ;#5D32: 28 05
        pop     de                                             ;#5D34: D1
        ld      bc,0                                           ;#5D35: 01 00 00
        ret                                                    ;#5D38: C9

ASM_PARSE_OPERAND2:
        ; Comma found: save operand-1, parse second operand into MEGA_ASM_OPERAND_VAL
        inc     c                                              ;#5D39: 0C
        dec     c                                              ;#5D3A: 0D
        jr      z,ASM_OPERANDS_RAISE_ERR                       ;#5D3B: 28 3D
        push    hl                                             ;#5D3D: E5
        ld      hl,(MEGA_ASM_OPERAND_VAL)                      ;#5D3E: 2A 51 EC
        ex      (sp),hl                                        ;#5D41: E3
        call    ASM_PARSE_OPERAND                              ;#5D42: CD 85 5D
        inc     c                                              ;#5D45: 0C
        dec     c                                              ;#5D46: 0D
        jr      z,ASM_OPERANDS_RAISE_ERR                       ;#5D47: 28 31
        call    ASM_CHECK_EOL_OR_COMMENT                       ;#5D49: CD 7D 5D
        push    af                                             ;#5D4C: F5
        ld      a,c                                            ;#5D4D: 79
        cp      0F8h                                           ;#5D4E: FE F8
        jr      z,ASM_OPERAND2_QUOTE                           ;#5D50: 28 0F
        pop     af                                             ;#5D52: F1
        jr      nz,ASM_OPERANDS_RAISE_ERR                      ;#5D53: 20 25
        ld      a,c                                            ;#5D55: 79
        and     0FEh                                           ;#5D56: E6 FE
        cp      30h                                            ;#5D58: FE 30
        pop     hl                                             ;#5D5A: E1
        pop     de                                             ;#5D5B: D1
        ret     z                                              ;#5D5C: C8
        ld      (MEGA_ASM_OPERAND_VAL),hl                      ;#5D5D: 22 51 EC
        ret                                                    ;#5D60: C9

ASM_OPERAND2_QUOTE:
        ; C=0F8h special path: require trailing `'` (quoted-char operand form), else raise
        pop     af                                             ;#5D61: F1
        cp      "'"                                            ;#5D62: FE 27
        jr      nz,ASM_OPERANDS_RAISE_ERR                      ;#5D64: 20 14
        inc     hl                                             ;#5D66: 23
        call    ASM_CHECK_EOL_OR_COMMENT                       ;#5D67: CD 7D 5D
        pop     hl                                             ;#5D6A: E1
        pop     de                                             ;#5D6B: D1
        ret     z                                              ;#5D6C: C8
        jr      ASM_OPERANDS_RAISE_ERR                         ;#5D6D: 18 0B

ASM_PARSE_OPERAND_AND_SEP:
        ; Parse one operand, then consume comma-or-end via ASM_CHECK_SEP_OR_END
        call    ASM_PARSE_OPERAND                              ;#5D6F: CD 85 5D
ASM_CHECK_SEP_OR_END:
        ; Expect ',' (advance) or EOL/';' (return Z); raise ASM_ERROR_RAISE otherwise
        call    ASM_CHECK_EOL_OR_COMMENT                       ;#5D72: CD 7D 5D
        ret     z                                              ;#5D75: C8
        cp      ","                                            ;#5D76: FE 2C
        inc     hl                                             ;#5D78: 23
        ret     z                                              ;#5D79: C8
ASM_OPERANDS_RAISE_ERR:
        ; jr trampoline to ASM_ERROR_RAISE — 8 ASM_PARSE_OPERANDS branches converge here
        jp      ASM_ERROR_RAISE                                ;#5D7A: C3 BC 5B

ASM_CHECK_EOL_OR_COMMENT:
        ; Skip spaces then test (HL): Z set if NUL or `;` (line done)
        call    SKIP_SPACES_RAW                                ;#5D7D: CD 0E 5C
        or      a                                              ;#5D80: B7
        ret     z                                              ;#5D81: C8
        cp      ";"                                            ;#5D82: FE 3B
        ret                                                    ;#5D84: C9

ASM_PARSE_OPERAND:
        ; Skip spaces; dispatch on '(' (indirect mode) or fall into label-name parser
        call    SKIP_SPACES_RAW                                ;#5D85: CD 0E 5C
        cp      "("                                            ;#5D88: FE 28
        jr      z,ASM_PARSE_OPERAND_PAREN                      ;#5D8A: 28 1B
ASM_PARSE_OPERAND_BODY:
        ; Operand-parse body — entered directly to parse contents of `(…)` indirect
        call    PARSE_LABEL_NAME                               ;#5D8C: CD D9 5B
        cp      ":"                                            ;#5D8F: FE 3A
        jr      z,ASM_OPERANDS_RAISE_ERR                       ;#5D91: 28 E7
        call    ASM_CLEAR_OPERAND_CELLS                        ;#5D93: CD 36 58
        cp      b                                              ;#5D96: B8
        jr      z,ASM_PARSE_EXPRESSION                         ;#5D97: 28 44
        push    hl                                             ;#5D99: E5
        call    ASM_LOOKUP_REG_NAME                            ;#5D9A: CD 23 5E
        pop     hl                                             ;#5D9D: E1
        ret     c                                              ;#5D9E: D8
        push    hl                                             ;#5D9F: E5
        call    RESOLVE_LABEL_VALUE                            ;#5DA0: CD 89 5C
        pop     hl                                             ;#5DA3: E1
        jp      ASM_EXPR_ACCUMULATE                            ;#5DA4: C3 18 5E

ASM_PARSE_OPERAND_PAREN:
        ; '(' arm — skip '(', recurse into body, may consume IX/IY displacement
        inc     hl                                             ;#5DA7: 23
        call    SKIP_SPACES_RAW                                ;#5DA8: CD 0E 5C
        call    ASM_PARSE_OPERAND_BODY                         ;#5DAB: CD 8C 5D
        inc     c                                              ;#5DAE: 0C
        dec     c                                              ;#5DAF: 0D
        jr      z,ASM_OPERANDS_RAISE_ERR                       ;#5DB0: 28 C8
        bit     2,c                                            ;#5DB2: CB 51
        jr      z,ASM_PARSE_OPERAND_CLOSE_PAREN                ;#5DB4: 28 0E
        push    bc                                             ;#5DB6: C5
        call    ASM_PARSE_EXPRESSION                           ;#5DB7: CD DD 5D
        pop     bc                                             ;#5DBA: C1
        call    ASM_CHECK_SIGNED_BYTE                          ;#5DBB: CD 83 5A
        ld      (MEGA_ASM_IXY_DISP),a                          ;#5DBE: 32 53 EC
        call    nz,ASM_ERROR_SET_BIT2                          ;#5DC1: C4 A3 5B
ASM_PARSE_OPERAND_CLOSE_PAREN:
        ; After paren body — require closing ')', then refine reg category
        call    SKIP_SPACES_RAW                                ;#5DC4: CD 0E 5C
        cp      ")"                                            ;#5DC7: FE 29
        jr      nz,ASM_OPERANDS_RAISE_ERR                      ;#5DC9: 20 AF
        inc     hl                                             ;#5DCB: 23
        ld      b,0                                            ;#5DCC: 06 00
        inc     c                                              ;#5DCE: 0C
        ld      a,c                                            ;#5DCF: 79
        and     0F9h                                           ;#5DD0: E6 F9
        cp      0E1h                                           ;#5DD2: FE E1
        ret     nz                                             ;#5DD4: C0
        and     6                                              ;#5DD5: E6 06
        or      0B0h                                           ;#5DD7: F6 B0
        ld      c,a                                            ;#5DD9: 4F
        ld      b,1                                            ;#5DDA: 06 01
        ret                                                    ;#5DDC: C9

ASM_PARSE_EXPRESSION:
        ; Parse additive `term ('+'|'-' term)*` — result lands in MEGA_ASM_OPERAND_VAL
        call    SKIP_SPACES_RAW                                ;#5DDD: CD 0E 5C
        cp      "+"                                            ;#5DE0: FE 2B
        jr      z,ASM_EXPR_APPLY_OP                            ;#5DE2: 28 1E
        cp      "-"                                            ;#5DE4: FE 2D
        jr      z,ASM_EXPR_APPLY_OP                            ;#5DE6: 28 1A
        call    ASM_PARSE_VALUE                                ;#5DE8: CD B4 5E
        ld      bc,0                                           ;#5DEB: 01 00 00
        ret     c                                              ;#5DEE: D8
        ld      (MEGA_ASM_OPERAND_VAL),de                      ;#5DEF: ED 53 51 EC
ASM_EXPR_NEXT_TERM:
        ; Re-entry: skip spaces, look for next +/- operator (or terminate with bc=8030h)
        call    SKIP_SPACES_RAW                                ;#5DF3: CD 0E 5C
        cp      "+"                                            ;#5DF6: FE 2B
        jr      z,ASM_EXPR_APPLY_OP                            ;#5DF8: 28 08
        cp      "-"                                            ;#5DFA: FE 2D
        jr      z,ASM_EXPR_APPLY_OP                            ;#5DFC: 28 04
        ld      bc,8030h                                       ;#5DFE: 01 30 80
        ret                                                    ;#5E01: C9

ASM_EXPR_APPLY_OP:
        ; Operator (+/-) found — save sign, advance HL, parse next value, fold via add/sub
        ld      (MEGA_ASM_OP_SIGN),a                           ;#5E02: 32 56 EC
        inc     hl                                             ;#5E05: 23
        call    ASM_PARSE_VALUE                                ;#5E06: CD B4 5E
        jp      c,ASM_ERROR_RAISE                              ;#5E09: DA BC 5B
        ld      a,(MEGA_ASM_OP_SIGN)                           ;#5E0C: 3A 56 EC
        sub     "-"                                            ;#5E0F: D6 2D
        jr      nz,ASM_EXPR_ACCUMULATE                         ;#5E11: 20 05
        sub     e                                              ;#5E13: 93
        ld      e,a                                            ;#5E14: 5F
        sbc     a,d                                            ;#5E15: 9A
        sub     e                                              ;#5E16: 93
        ld      d,a                                            ;#5E17: 57
ASM_EXPR_ACCUMULATE:
        ; Add the (signed) parsed value (DE) into MEGA_ASM_OPERAND_VAL, loop for next term
        push    hl                                             ;#5E18: E5
        ld      hl,(MEGA_ASM_OPERAND_VAL)                      ;#5E19: 2A 51 EC
        add     hl,de                                          ;#5E1C: 19
        ld      (MEGA_ASM_OPERAND_VAL),hl                      ;#5E1D: 22 51 EC
        pop     hl                                             ;#5E20: E1
        jr      ASM_EXPR_NEXT_TERM                             ;#5E21: 18 D0

ASM_LOOKUP_REG_NAME:
        ; Compare MEGA_LABEL_NAME against ASM_REG_NAME_TABLE; B = register code on match
        ld      a,b                                            ;#5E23: 78
        cp      3                                              ;#5E24: FE 03
        ld      bc,0                                           ;#5E26: 01 00 00
        ret     nc                                             ;#5E29: D0
        ld      de,(MEGA_LABEL_NAME)                           ;#5E2A: ED 5B AF EC
        ld      hl,ASM_REG_NAME_TABLE                          ;#5E2E: 21 57 5E
ASM_LOOKUP_REG_RECORD:
        ; Per-record: read name byte 0, end-of-table check, compare vs DE low byte
        ld      a,(hl)                                         ;#5E31: 7E
        or      a                                              ;#5E32: B7
        ret     z                                              ;#5E33: C8
        cp      e                                              ;#5E34: BB
        inc     hl                                             ;#5E35: 23
        jr      nz,ASM_LOOKUP_REG_NEXT                         ;#5E36: 20 06
        ld      a,(hl)                                         ;#5E38: 7E
        cp      d                                              ;#5E39: BA
        inc     hl                                             ;#5E3A: 23
        jr      z,ASM_LOOKUP_REG_FOUND                         ;#5E3B: 28 06
        OVERLAP_CP                                             ;#5E3D: FE
ASM_LOOKUP_REG_NEXT:
        ; No match: advance HL past the 4-byte record, loop to next record
        inc     hl                                             ;#5E3E: 23
        inc     hl                                             ;#5E3F: 23
        inc     hl                                             ;#5E40: 23
        jr      ASM_LOOKUP_REG_RECORD                          ;#5E41: 18 EE

ASM_LOOKUP_REG_FOUND:
        ; Match: read register-family code into B, advance HL past the mask byte
        ld      b,(hl)                                         ;#5E43: 46
        inc     hl                                             ;#5E44: 23
        ld      c,(hl)                                         ;#5E45: 4E
        res     7,b                                            ;#5E46: CB B8
        ld      a,c                                            ;#5E48: 79
        and     6                                              ;#5E49: E6 06
        push    de                                             ;#5E4B: D5
        ld      e,a                                            ;#5E4C: 5F
        ld      a,(MEGA_ASM_OPC_FLAGS)                         ;#5E4D: 3A 55 EC
        or      e                                              ;#5E50: B3
        ld      (MEGA_ASM_OPC_FLAGS),a                         ;#5E51: 32 55 EC
        pop     de                                             ;#5E54: D1
        scf                                                    ;#5E55: 37
        ret                                                    ;#5E56: C9

ASM_REG_NAME_TABLE:
        ; Table of 4-byte register-name records (name[2]+code[2]); 00 terminator
        ; Format: FORMAT_ASM_REG_NAME
        ; - Used by ASM_REG_NAME_TABLE. Each record: 2 ASCII name chars (right-padded
        ; - with space for 1-letter names like 'B ', 'I '), then a register-family
        ; - type byte (rendered via the ARGUMENT_* equate when one matches), then
        ; - the bit-pre-positioned mask byte. 00-byte terminator at the tail. The
        ; - ASM_REG record is rendered with named macro params (requires the
        ; - ricbit/sjasmplus fork).
        ASM_REG name="B ", type=ARGUMENT_R8, mask=80h          ;#5E57: 42 20 81 80
        ASM_REG name="C ", type=ARGUMENT_R8, mask=88h          ;#5E5B: 43 20 81 88
        ASM_REG name="D ", type=ARGUMENT_R8, mask=90h          ;#5E5F: 44 20 81 90
        ASM_REG name="E ", type=ARGUMENT_R8, mask=98h          ;#5E63: 45 20 81 98
        ASM_REG name="H ", type=ARGUMENT_R8, mask=0A0h         ;#5E67: 48 20 81 A0
        ASM_REG name="L ", type=ARGUMENT_R8, mask=0A8h         ;#5E6B: 4C 20 81 A8
        ASM_REG name="A ", type=ARGUMENT_R8, mask=0B8h         ;#5E6F: 41 20 81 B8
        ASM_REG name="I ", type=ARGUMENT_IR, mask=10h          ;#5E73: 49 20 80 10
        ASM_REG name="R ", type=ARGUMENT_IR, mask=20h          ;#5E77: 52 20 80 20
        ASM_REG name="BC", type=ARGUMENT_BC_DE, mask=0C0h      ;#5E7B: 42 43 BE C0
        ASM_REG name="DE", type=ARGUMENT_BC_DE, mask=0D0h      ;#5E7F: 44 45 BE D0
        ASM_REG name="HL", type=ARGUMENT_HL, mask=0E0h         ;#5E83: 48 4C B2 E0
        ASM_REG name="SP", type=ARGUMENT_SP, mask=0F0h         ;#5E87: 53 50 9E F0
        ASM_REG name="AF", type=ARGUMENT_AF, mask=0F8h         ;#5E8B: 41 46 A0 F8
        ASM_REG name="IX", type=ARGUMENT_IX, mask=0E4h         ;#5E8F: 49 58 B4 E4
        ASM_REG name="IY", type=ARGUMENT_IY, mask=0E6h         ;#5E93: 49 59 B8 E6
        ASM_REG name="NZ", type=ARGUMENT_COND, mask=40h        ;#5E97: 4E 5A C0 40
        ASM_REG name="Z ", type=ARGUMENT_COND, mask=48h        ;#5E9B: 5A 20 C0 48
        ASM_REG name="NC", type=ARGUMENT_COND, mask=50h        ;#5E9F: 4E 43 C0 50
        ASM_REG name="PO", type=ARGUMENT_COND, mask=60h        ;#5EA3: 50 4F C0 60
        ASM_REG name="PE", type=ARGUMENT_COND, mask=68h        ;#5EA7: 50 45 C0 68
        ASM_REG name="P ", type=ARGUMENT_COND, mask=70h        ;#5EAB: 50 20 C0 70
        ASM_REG name="M ", type=ARGUMENT_COND, mask=78h        ;#5EAF: 4D 20 C0 78
        db      0                                              ;#5EB3: 00

ASM_PARSE_VALUE:
        ; Parse one term: label-ref / '..'-string / $-PC / numeric (dec/H-hex/B-bin)
        call    PARSE_LABEL_NAME                               ;#5EB4: CD D9 5B
        inc     b                                              ;#5EB7: 04
        dec     b                                              ;#5EB8: 05
        jp      nz,ASM_PARSE_LABEL_REF                         ;#5EB9: C2 45 5F
        ld      a,(hl)                                         ;#5EBC: 7E
        cp      "'"                                            ;#5EBD: FE 27
        jr      z,ASM_PARSE_STRING_LIT                         ;#5EBF: 28 77
        cp      "$"                                            ;#5EC1: FE 24
        jp      z,ASM_PARSE_VALUE_DOLLAR                       ;#5EC3: CA 4B 5F
        cp      "0"                                            ;#5EC6: FE 30
        ret     c                                              ;#5EC8: D8
        cp      ":"                                            ;#5EC9: FE 3A
        ccf                                                    ;#5ECB: 3F
        ret     c                                              ;#5ECC: D8
        ld      de,MEGA_LABEL_NAME                             ;#5ECD: 11 AF EC
        ld      c,0                                            ;#5ED0: 0E 00
ASM_HEX_LIT_DIGIT:
        ; ASM_PARSE_VALUE hex-literal per-digit loop body: `sub "0"`, store, advance
        sub     "0"                                            ;#5ED2: D6 30
        ld      (de),a                                         ;#5ED4: 12
        inc     de                                             ;#5ED5: 13
        inc     hl                                             ;#5ED6: 23
        ld      a,(hl)                                         ;#5ED7: 7E
        cp      "0"                                            ;#5ED8: FE 30
        jr      c,ASM_HEX_LIT_FINALIZE                         ;#5EDA: 38 30
        cp      "2"                                            ;#5EDC: FE 32
        jr      c,ASM_HEX_LIT_DIGIT                            ;#5EDE: 38 F2
        cp      "B"                                            ;#5EE0: FE 42
        jr      z,ASM_HEX_LIT_B_CHECK                          ;#5EE2: 28 17
ASM_HEX_LIT_2_THRU_9:
        ; After 2-9 digit branch: increment digit count C, continue to ASM_HEX_LIT_DIGIT
        inc     c                                              ;#5EE4: 0C
        cp      "9"+1                                          ;#5EE5: FE 3A
        jr      c,ASM_HEX_LIT_DIGIT                            ;#5EE7: 38 E9
        cp      "A"                                            ;#5EE9: FE 41
        jr      c,ASM_HEX_LIT_FINALIZE                         ;#5EEB: 38 1F
        inc     b                                              ;#5EED: 04
        cp      "H"                                            ;#5EEE: FE 48
        jr      z,ASM_HEX_LIT_H_SUFFIX                         ;#5EF0: 28 20
        cp      "F"+1                                          ;#5EF2: FE 47
        jp      nc,ASM_ERROR_RAISE                             ;#5EF4: D2 BC 5B
        sub     7                                              ;#5EF7: D6 07
        jr      ASM_HEX_LIT_DIGIT                              ;#5EF9: 18 D7

ASM_HEX_LIT_B_CHECK:
        ; 'B' after digits: count C, continue if more alpha-hex, else binary suffix
        inc     c                                              ;#5EFB: 0C
        dec     c                                              ;#5EFC: 0D
        jr      nz,ASM_HEX_LIT_2_THRU_9                        ;#5EFD: 20 E5
        inc     hl                                             ;#5EFF: 23
        ld      a,(hl)                                         ;#5F00: 7E
        dec     hl                                             ;#5F01: 2B
        call    IS_HEX_CHAR_AF                                 ;#5F02: CD 71 5F
        ld      a,"B"                                          ;#5F05: 3E 42
        jr      nc,ASM_HEX_LIT_2_THRU_9                        ;#5F07: 30 DB
        jp      ASM_PARSE_DECIMAL                              ;#5F09: C3 54 5F

ASM_HEX_LIT_FINALIZE:
        ; Digit string done: verify B (alpha count), write 80h terminator into label buf
        xor     a                                              ;#5F0C: AF
        cp      b                                              ;#5F0D: B8
        jp      nz,ASM_ERROR_RAISE                             ;#5F0E: C2 BC 5B
        OVERLAP_CP                                             ;#5F11: FE
ASM_HEX_LIT_H_SUFFIX:
        ; 'H' hex suffix found — consume, jp to digit-folding loop at 5F16
        inc     hl                                             ;#5F12: 23
        ld      a,80h                                          ;#5F13: 3E 80
        ld      (de),a                                         ;#5F15: 12
        push    hl                                             ;#5F16: E5
        ld      hl,MEGA_LABEL_NAME                             ;#5F17: 21 AF EC
        ld      de,0                                           ;#5F1A: 11 00 00
ASM_HEX_FOLD_LOOP:
        ; Hex digit-fold loop head — read char from MEGA_LABEL_NAME, M=done
        ld      a,(hl)                                         ;#5F1D: 7E
        inc     hl                                             ;#5F1E: 23
        or      a                                              ;#5F1F: B7
        jp      m,ASM_VALUE_DONE                               ;#5F20: FA 51 5F
        push    hl                                             ;#5F23: E5
        ld      h,d                                            ;#5F24: 62
        ld      l,e                                            ;#5F25: 6B
        add     hl,hl                                          ;#5F26: 29
        add     hl,hl                                          ;#5F27: 29
        inc     b                                              ;#5F28: 04
        dec     b                                              ;#5F29: 05
        jr      z,ASM_HEX_FOLD_NO_X4                           ;#5F2A: 28 02
        add     hl,hl                                          ;#5F2C: 29
        OVERLAP_CP                                             ;#5F2D: FE
ASM_HEX_FOLD_NO_X4:
        ; B==0 (no `H` suffix) arm — skip extra add hl,hl × 2 (decimal vs hex multiply)
        add     hl,de                                          ;#5F2E: 19
        add     hl,hl                                          ;#5F2F: 29
        ld      e,a                                            ;#5F30: 5F
        ld      d,0                                            ;#5F31: 16 00
        add     hl,de                                          ;#5F33: 19
        ex      de,hl                                          ;#5F34: EB
        pop     hl                                             ;#5F35: E1
        jr      ASM_HEX_FOLD_LOOP                              ;#5F36: 18 E5

ASM_PARSE_STRING_LIT:
        ; `'…'` string-literal arm of ASM_PARSE_VALUE — STRING_LIT_END_CHECK, accumulate
        inc     hl                                             ;#5F38: 23
        ld      de,0                                           ;#5F39: 11 00 00
ASM_PARSE_STR_LOOP:
        ; String-lit accumulate loop — end-check then shift char into DE
        call    STRING_LIT_END_CHECK                           ;#5F3C: CD 25 58
        ret     nc                                             ;#5F3F: D0
        ld      d,e                                            ;#5F40: 53
        ld      e,(hl)                                         ;#5F41: 5E
        inc     hl                                             ;#5F42: 23
        jr      ASM_PARSE_STR_LOOP                             ;#5F43: 18 F7

ASM_PARSE_LABEL_REF:
        ; Identifier parsed: RESOLVE_LABEL_VALUE then ASM_VALUE_DONE
        push    hl                                             ;#5F45: E5
        call    RESOLVE_LABEL_VALUE                            ;#5F46: CD 89 5C
        jr      ASM_VALUE_DONE                                 ;#5F49: 18 06

ASM_PARSE_VALUE_DOLLAR:
        ; '$' arm: load DE = MEGA_DISASM_INSTR_START (= PC), ret via ASM_VALUE_DONE
        inc     hl                                             ;#5F4B: 23
        push    hl                                             ;#5F4C: E5
        ld      de,(MEGA_DISASM_INSTR_START)                   ;#5F4D: ED 5B 60 EC
ASM_VALUE_DONE:
        ; Common tail of the value-parse arms: pop hl, or a (CF=0), ret with DE=value
        pop     hl                                             ;#5F51: E1
        or      a                                              ;#5F52: B7
        ret                                                    ;#5F53: C9

ASM_PARSE_DECIMAL:
        ; Decimal-literal arm — write 80h term, then BCD-style fold via rrca/rl
        inc     hl                                             ;#5F54: 23
        ld      a,80h                                          ;#5F55: 3E 80
        ld      (de),a                                         ;#5F57: 12
        push    hl                                             ;#5F58: E5
        ld      hl,MEGA_LABEL_NAME                             ;#5F59: 21 AF EC
        ld      de,0                                           ;#5F5C: 11 00 00
        ld      b,11h                                          ;#5F5F: 06 11
ASM_PARSE_DECIMAL_DIGIT:
        ; Per-digit BCD fold body of decimal-literal parse
        ld      a,(hl)                                         ;#5F61: 7E
        or      a                                              ;#5F62: B7
        jp      m,ASM_VALUE_DONE                               ;#5F63: FA 51 5F
        inc     hl                                             ;#5F66: 23
        rrca                                                   ;#5F67: 0F
        rl      e                                              ;#5F68: CB 13
        rl      d                                              ;#5F6A: CB 12
        djnz    ASM_PARSE_DECIMAL_DIGIT                        ;#5F6C: 10 F3
        jp      ASM_ERROR_OPERAND                              ;#5F6E: C3 B9 5B

IS_HEX_CHAR_AF:
        ; Test A: CF=0 if it's a hex digit ('0'..'9' or 'A'..'F'); skips 'H' as suffix
        cp      "0"                                            ;#5F71: FE 30
        ret     c                                              ;#5F73: D8
        cp      "9"+1                                          ;#5F74: FE 3A
        ccf                                                    ;#5F76: 3F
        ret     nc                                             ;#5F77: D0
        cp      "A"                                            ;#5F78: FE 41
        ret     c                                              ;#5F7A: D8
        cp      "H"                                            ;#5F7B: FE 48
        ret     z                                              ;#5F7D: C8
        cp      "F"+1                                          ;#5F7E: FE 47
        ccf                                                    ;#5F80: 3F
        ret                                                    ;#5F81: C9

ASM_LOOKUP_MNEMONIC:
        ; Index MNEMONIC_FIRST_LETTER_TABLE by label[0]-'A'; DE = sub-table pointer
        ld      a,(MEGA_LABEL_NAME)                            ;#5F82: 3A AF EC
        sub     "A"                                            ;#5F85: D6 41
        jp      c,ASM_ERROR_NO_MNEMONIC                        ;#5F87: DA B6 5B
        cp      18h                                            ;#5F8A: FE 18
        jp      nc,ASM_ERROR_NO_MNEMONIC                       ;#5F8C: D2 B6 5B
        ld      e,a                                            ;#5F8F: 5F
        ld      d,0                                            ;#5F90: 16 00
        ld      hl,MNEMONIC_FIRST_LETTER_TABLE                 ;#5F92: 21 C8 5F
        add     hl,de                                          ;#5F95: 19
        add     hl,de                                          ;#5F96: 19
        ld      e,(hl)                                         ;#5F97: 5E
        inc     hl                                             ;#5F98: 23
        ld      d,(hl)                                         ;#5F99: 56
ASM_MNEMONIC_MATCH_RECORD:
        ; Per-record matcher in MNEMONIC_TABLE_x: reset HL→ECB0, compare-and-advance
        ld      hl,MEGA_LABEL_NAME_TAIL                        ;#5F9A: 21 B0 EC
ASM_MNEMONIC_NAME_CMP:
        ; Per-char compare body: read next name char, advance, jr-if-still-matching
        ld      a,(de)                                         ;#5F9D: 1A
        inc     de                                             ;#5F9E: 13
        cp      (hl)                                           ;#5F9F: BE
        inc     hl                                             ;#5FA0: 23
        jr      z,ASM_MNEMONIC_NAME_CMP                        ;#5FA1: 28 FA
        or      a                                              ;#5FA3: B7
        jp      z,ASM_ERROR_NO_MNEMONIC                        ;#5FA4: CA B6 5B
        jp      p,ASM_MNEMONIC_SKIP_REST                       ;#5FA7: F2 B4 5F
        dec     hl                                             ;#5FAA: 2B
        ld      a,(hl)                                         ;#5FAB: 7E
        cp      " "                                            ;#5FAC: FE 20
        jp      z,ASM_MNEMONIC_MATCH_DONE                      ;#5FAE: CA BC 5F
        inc     de                                             ;#5FB1: 13
        jr      ASM_MNEMONIC_MATCH_RECORD                      ;#5FB2: 18 E6

ASM_MNEMONIC_SKIP_REST:
        ; No match: walk DE past rest of mnemonic name (until bit-7 set), advance, loop
        ld      a,(de)                                         ;#5FB4: 1A
        inc     de                                             ;#5FB5: 13
        rla                                                    ;#5FB6: 17
        jr      nc,ASM_MNEMONIC_SKIP_REST                      ;#5FB7: 30 FB
        inc     de                                             ;#5FB9: 13
        jr      ASM_MNEMONIC_MATCH_RECORD                      ;#5FBA: 18 DE

ASM_MNEMONIC_MATCH_DONE:
        ; Match: read opcode byte into EC58, save flag at MEGA_DISASM_OPCODE, ret
        ld      a,(de)                                         ;#5FBC: 1A
        ld      (MEGA_ASM_IXY_PREFIX),a                        ;#5FBD: 32 58 EC
        dec     de                                             ;#5FC0: 1B
        ld      a,(de)                                         ;#5FC1: 1A
        and     7Fh                                            ;#5FC2: E6 7F
        ld      (MEGA_DISASM_OPCODE),a                         ;#5FC4: 32 57 EC
        ret                                                    ;#5FC7: C9

MNEMONIC_FIRST_LETTER_TABLE:
        ; 24 pointers indexed by mnemonic first letter (A=0..X=23)
        dw      MNEMONIC_TABLE_A                               ;#5FC8: F8 5F
        dw      MNEMONIC_TABLE_B                               ;#5FCA: 05 60
        dw      MNEMONIC_TABLE_C                               ;#5FCC: 0A 60
        dw      MNEMONIC_TABLE_D                               ;#5FCE: 2D 60
        dw      MNEMONIC_TABLE_E                               ;#5FD0: 5B 60
        dw      MNEMONIC_NOT_FOUND                             ;#5FD2: 04 60
        dw      MNEMONIC_NOT_FOUND                             ;#5FD4: 04 60
        dw      MNEMONIC_TABLE_H                               ;#5FD6: 6E 60
        dw      MNEMONIC_TABLE_I                               ;#5FD8: 74 60
        dw      MNEMONIC_TABLE_J                               ;#5FDA: 91 60
        dw      MNEMONIC_NOT_FOUND                             ;#5FDC: 04 60
        dw      MNEMONIC_TABLE_L                               ;#5FDE: 98 60
        dw      MNEMONIC_NOT_FOUND                             ;#5FE0: 04 60
        dw      MNEMONIC_TABLE_N                               ;#5FE2: AE 60
        dw      MNEMONIC_TABLE_O                               ;#5FE4: B7 60
        dw      MNEMONIC_TABLE_P                               ;#5FE6: D7 60
        dw      MNEMONIC_NOT_FOUND                             ;#5FE8: 04 60
        dw      MNEMONIC_TABLE_R                               ;#5FEA: E1 60
        dw      MNEMONIC_TABLE_S                               ;#5FEC: 20 61
        dw      MNEMONIC_NOT_FOUND                             ;#5FEE: 04 60
        dw      MNEMONIC_NOT_FOUND                             ;#5FF0: 04 60
        dw      MNEMONIC_NOT_FOUND                             ;#5FF2: 04 60
        dw      MNEMONIC_NOT_FOUND                             ;#5FF4: 04 60
        dw      MNEMONIC_TABLE_X                               ;#5FF6: 3D 61

MNEMONIC_TABLE_A:
        ; Mnemonic sub-table for ADC/ADD/AND
        MNEMONIC "A", "DC", ID_ASM_ADC_SBC, Z80_ADC_A_N        ;#5FF8: 44 43 86 CE
        MNEMONIC "A", "DD", ID_ASM_ADD, Z80_ADD_A_N            ;#5FFC: 44 44 87 C6
        MNEMONIC "A", "ND", ID_ASM_ARITH_A, Z80_AND_N          ;#6000: 4E 44 82 E6
MNEMONIC_NOT_FOUND:
        ; Stub returned by MNEMONIC_FIRST_LETTER_TABLE for letters with no mnemonic
        db      0                                              ;#6004: 00

MNEMONIC_TABLE_B:
        ; Mnemonic sub-table for BIT
        MNEMONIC "B", "IT", ID_ASM_BIT, Z80_BIT_BASE           ;#6005: 49 54 84 40
        db      0                                              ;#6009: 00

MNEMONIC_TABLE_C:
        ; Mnemonic sub-table for CALL/CCF/CP/CPD/CPI/CPDR/CPIR/CPL
        MNEMONIC "C", "ALL", ID_ASM_CALL, Z80_CALL             ;#600A: 41 4C 4C 89 CD
        MNEMONIC "C", "CF", ID_ASM_PLAIN, Z80_CCF              ;#600F: 43 46 80 3F
        MNEMONIC "C", "P", ID_ASM_ARITH_A, Z80_CP_N            ;#6013: 50 82 FE
        MNEMONIC "C", "PD", ID_ASM_ED, Z80_CPD                 ;#6016: 50 44 81 A9
        MNEMONIC "C", "PDR", ID_ASM_ED, Z80_CPDR               ;#601A: 50 44 52 81 B9
        MNEMONIC "C", "PI", ID_ASM_ED, Z80_CPI                 ;#601F: 50 49 81 A1
        MNEMONIC "C", "PIR", ID_ASM_ED, Z80_CPIR               ;#6023: 50 49 52 81 B1
        MNEMONIC "C", "PL", ID_ASM_PLAIN, Z80_CPL              ;#6028: 50 4C 80 2F
        db      0                                              ;#602C: 00

MNEMONIC_TABLE_D:
        ; Mnemonic sub-table for DAA/DEC/DI/DJNZ
        MNEMONIC "D", "AA", ID_ASM_PLAIN, Z80_DAA              ;#602D: 41 41 80 27
        MNEMONIC "D", "EC", ID_ASM_INC_DEC, Z80_DEC_R          ;#6031: 45 43 83 05
        MNEMONIC "D", "I", ID_ASM_PLAIN, Z80_DI                ;#6035: 49 80 F3
        MNEMONIC "D", "JNZ", ID_ASM_DJNZ, Z80_DJNZ             ;#6038: 4A 4E 5A 8C 10
        MNEMONIC "D", "EFB", ID_ASM_DEFB, Z80_PSEUDO_OP        ;#603D: 45 46 42 9F 00
        MNEMONIC "D", "EFM", ID_ASM_DEFB, Z80_PSEUDO_OP        ;#6042: 45 46 4D 9F 00
        MNEMONIC "D", "EFW", ID_ASM_DEFW, Z80_PSEUDO_OP        ;#6047: 45 46 57 9E 00
        MNEMONIC "D", "EFS", ID_ASM_DEFS, Z80_PSEUDO_OP        ;#604C: 45 46 53 96 00
        MNEMONIC "D", "B", ID_ASM_DEFB, Z80_PSEUDO_OP          ;#6051: 42 9F 00
        MNEMONIC "D", "W", ID_ASM_DEFW, Z80_PSEUDO_OP          ;#6054: 57 9E 00
        MNEMONIC "D", "S", ID_ASM_DEFS, Z80_PSEUDO_OP          ;#6057: 53 96 00
        db      0                                              ;#605A: 00

MNEMONIC_TABLE_E:
        ; Mnemonic sub-table for EI/EX/EXX
        MNEMONIC "E", "I", ID_ASM_PLAIN, Z80_EI                ;#605B: 49 80 FB
        MNEMONIC "E", "X", ID_ASM_EX, Z80_EX_SP_HL             ;#605E: 58 8E E3
        MNEMONIC "E", "XX", ID_ASM_PLAIN, Z80_EXX              ;#6061: 58 58 80 D9
        MNEMONIC "E", "ND", ID_ASM_END, Z80_PSEUDO_OP          ;#6065: 4E 44 95 00
        MNEMONIC "E", "QU", ID_ASM_EQU, Z80_PSEUDO_OP          ;#6069: 51 55 97 00
        db      0                                              ;#606D: 00

MNEMONIC_TABLE_H:
        ; Mnemonic sub-table for HALT
        MNEMONIC "H", "ALT", ID_ASM_PLAIN, Z80_HALT            ;#606E: 41 4C 54 80 76
        db      0                                              ;#6073: 00

MNEMONIC_TABLE_I:
        ; Mnemonic sub-table for IM/IN/INC/IND/INDR/INI/INIR
        MNEMONIC "I", "M", ID_ASM_IM, Z80_IM_0_OPC             ;#6074: 4D 8F 46
        MNEMONIC "I", "N", ID_ASM_IN, Z80_IN_A_N               ;#6077: 4E 90 DB
        MNEMONIC "I", "NC", ID_ASM_INC_DEC, Z80_INC_R          ;#607A: 4E 43 83 04
        MNEMONIC "I", "ND", ID_ASM_ED, Z80_IND                 ;#607E: 4E 44 81 AA
        MNEMONIC "I", "NDR", ID_ASM_ED, Z80_INDR               ;#6082: 4E 44 52 81 BA
        MNEMONIC "I", "NI", ID_ASM_ED, Z80_INI                 ;#6087: 4E 49 81 A2
        MNEMONIC "I", "NIR", ID_ASM_ED, Z80_INIR               ;#608B: 4E 49 52 81 B2
        db      0                                              ;#6090: 00

MNEMONIC_TABLE_J:
        ; Mnemonic sub-table for JP/JR
        MNEMONIC "J", "P", ID_ASM_JP, Z80_JP                   ;#6091: 50 8A C3
        MNEMONIC "J", "R", ID_ASM_JR, Z80_JR                   ;#6094: 52 8B 18
        db      0                                              ;#6097: 00

MNEMONIC_TABLE_L:
        ; Mnemonic sub-table for LD/LDD/LDDR/LDI/LDIR
        MNEMONIC "L", "D", ID_ASM_LD, Z80_LD_R_R               ;#6098: 44 88 40
        MNEMONIC "L", "DD", ID_ASM_ED, Z80_LDD                 ;#609B: 44 44 81 A8
        MNEMONIC "L", "DDR", ID_ASM_ED, Z80_LDDR               ;#609F: 44 44 52 81 B8
        MNEMONIC "L", "DI", ID_ASM_ED, Z80_LDI                 ;#60A4: 44 49 81 A0
        MNEMONIC "L", "DIR", ID_ASM_ED, Z80_LDIR               ;#60A8: 44 49 52 81 B0
        db      0                                              ;#60AD: 00

MNEMONIC_TABLE_N:
        ; Mnemonic sub-table for NEG/NOP
        MNEMONIC "N", "EG", ID_ASM_ED, Z80_NEG                 ;#60AE: 45 47 81 44
        MNEMONIC "N", "OP", ID_ASM_PLAIN, Z80_NOP              ;#60B2: 4F 50 80 00
        db      0                                              ;#60B6: 00

MNEMONIC_TABLE_O:
        ; Mnemonic sub-table for OR/OTDR/OTIR/OUT/OUTD/OUTI
        MNEMONIC "O", "R", ID_ASM_ARITH_A, Z80_OR_N            ;#60B7: 52 82 F6
        MNEMONIC "O", "TDR", ID_ASM_ED, Z80_OTDR               ;#60BA: 54 44 52 81 BB
        MNEMONIC "O", "TIR", ID_ASM_ED, Z80_OTIR               ;#60BF: 54 49 52 81 B3
        MNEMONIC "O", "UT", ID_ASM_OUT, Z80_OUT_N_A            ;#60C4: 55 54 91 D3
        MNEMONIC "O", "UTD", ID_ASM_ED, Z80_OUTD               ;#60C8: 55 54 44 81 AB
        MNEMONIC "O", "UTI", ID_ASM_ED, Z80_OUTI               ;#60CD: 55 54 49 81 A3
        MNEMONIC "O", "RG", ID_ASM_ORG, Z80_PSEUDO_OP          ;#60D2: 52 47 94 00
        db      0                                              ;#60D6: 00

MNEMONIC_TABLE_P:
        ; Mnemonic sub-table for POP/PUSH
        MNEMONIC "P", "OP", ID_ASM_PUSH_POP, Z80_POP_RP        ;#60D7: 4F 50 92 C1
        MNEMONIC "P", "USH", ID_ASM_PUSH_POP, Z80_PUSH_RP      ;#60DB: 55 53 48 92 C5
        db      0                                              ;#60E0: 00

MNEMONIC_TABLE_R:
        ; Mnemonic sub-table for RES/RET/RETI/RETN/RL/RLA/RLC/RLD/RR/RST etc.
        MNEMONIC "R", "ES", ID_ASM_BIT, Z80_RES_BASE           ;#60E1: 45 53 84 80
        MNEMONIC "R", "ET", ID_ASM_RET, Z80_RET                ;#60E5: 45 54 8D C9
        MNEMONIC "R", "ETI", ID_ASM_ED, Z80_RETI               ;#60E9: 45 54 49 81 4D
        MNEMONIC "R", "ETN", ID_ASM_ED, Z80_RETN               ;#60EE: 45 54 4E 81 45
        MNEMONIC "R", "L", ID_ASM_SHIFT, Z80_RL_BASE           ;#60F3: 4C 85 10
        MNEMONIC "R", "LA", ID_ASM_PLAIN, Z80_RLA              ;#60F6: 4C 41 80 17
        MNEMONIC "R", "LC", ID_ASM_SHIFT, Z80_RLC_BASE         ;#60FA: 4C 43 85 00
        MNEMONIC "R", "LCA", ID_ASM_PLAIN, Z80_RLCA            ;#60FE: 4C 43 41 80 07
        MNEMONIC "R", "LD", ID_ASM_ED, Z80_RLD                 ;#6103: 4C 44 81 6F
        MNEMONIC "R", "R", ID_ASM_SHIFT, Z80_RR_BASE           ;#6107: 52 85 18
        MNEMONIC "R", "RA", ID_ASM_PLAIN, Z80_RRA              ;#610A: 52 41 80 1F
        MNEMONIC "R", "RC", ID_ASM_SHIFT, Z80_RRC_BASE         ;#610E: 52 43 85 08
        MNEMONIC "R", "RCA", ID_ASM_PLAIN, Z80_RRCA            ;#6112: 52 43 41 80 0F
        MNEMONIC "R", "RD", ID_ASM_ED, Z80_RRD                 ;#6117: 52 44 81 67
        MNEMONIC "R", "ST", ID_ASM_RST, Z80_RST                ;#611B: 53 54 93 C7
        db      0                                              ;#611F: 00

MNEMONIC_TABLE_S:
        ; Mnemonic sub-table for SBC/SCF/SET/SLA/SRA/SRL/SUB
        MNEMONIC "S", "BC", ID_ASM_ADC_SBC, Z80_SBC_A_N        ;#6120: 42 43 86 DE
        MNEMONIC "S", "CF", ID_ASM_PLAIN, Z80_SCF              ;#6124: 43 46 80 37
        MNEMONIC "S", "ET", ID_ASM_BIT, Z80_SET_BASE           ;#6128: 45 54 84 C0
        MNEMONIC "S", "LA", ID_ASM_SHIFT, Z80_SLA_BASE         ;#612C: 4C 41 85 20
        MNEMONIC "S", "RA", ID_ASM_SHIFT, Z80_SRA_BASE         ;#6130: 52 41 85 28
        MNEMONIC "S", "RL", ID_ASM_SHIFT, Z80_SRL_BASE         ;#6134: 52 4C 85 38
        MNEMONIC "S", "UB", ID_ASM_ARITH_A, Z80_SUB_N          ;#6138: 55 42 82 D6
        db      0                                              ;#613C: 00

MNEMONIC_TABLE_X:
        ; Mnemonic sub-table for XOR
        MNEMONIC "X", "OR", ID_ASM_ARITH_A, Z80_XOR_N          ;#613D: 4F 52 82 EE
        db      0                                              ;#6141: 00

MEGA_PCMD_LP:
        ; Prompt command "LP" — enable printer echo (sets state bit 1) then fall into L
        set     1,(ix)                                         ;#6142: DD CB 00 CE
MEGA_PCMD_L:
        ; Prompt command "L" — list one screenful of source (10 lines from cursor)
        call    SKIP_SPACES                                    ;#6146: CD F3 43
        jr      nz,MEGA_PCMD_L_PARSE_RANGE                     ;#6149: 20 2A
        ld      de,(MEGA_DISASM_LAST_END)                      ;#614B: ED 5B 45 EC
MEGA_PCMD_L_DEFAULT:
        ; No-arg L — cursor=DISASM_LAST_END, end=10 lines, fall into per-line loop
        ld      (MEGA_DISASM_CURSOR),de                        ;#614F: ED 53 5E EC
        ld      a,"\n"                                         ;#6153: 3E 0A
        ld      (MEGA_LINE_RANGE_END),a                        ;#6155: 32 22 EC
MEGA_PCMD_L_LINE_LOOP:
        ; Per-line body: init, print disasm line, check interrupt, count down
        call    DISASM_INIT_INSTRUCTION_STATE                  ;#6158: CD D2 61
        call    PRINT_DISASM_LINE_SIMPLE                       ;#615B: CD C5 61
        call    CHECK_USER_INTERRUPT                           ;#615E: CD 9D 42
        jr      c,MEGA_PCMD_L_DONE                             ;#6161: 38 50
        ld      a,(DISASM_SPECIAL_MATCH_FLAG)                  ;#6163: 3A 47 EC
        or      a                                              ;#6166: B7
        call    nz,PRINT_BLANK_DISASM_LINE                     ;#6167: C4 BA 61
        ld      a,(MEGA_LINE_RANGE_END)                        ;#616A: 3A 22 EC
        dec     a                                              ;#616D: 3D
        ld      (MEGA_LINE_RANGE_END),a                        ;#616E: 32 22 EC
        jr      nz,MEGA_PCMD_L_LINE_LOOP                       ;#6171: 20 E5
        jr      MEGA_PCMD_L_DONE                               ;#6173: 18 3E

MEGA_PCMD_L_PARSE_RANGE:
        ; L arg form: parse start [,end] then disasm until end addr or interrupt
        call    PARSE_HEX_WORD                                 ;#6175: CD BA 50
        jp      c,SYNTAX_ERROR_LF                              ;#6178: DA 47 43
        ld      a,(hl)                                         ;#617B: 7E
        cp      0                                              ;#617C: FE 00
        jr      z,MEGA_PCMD_L_DEFAULT                          ;#617E: 28 CF
        cp      ","                                            ;#6180: FE 2C
        jp      nz,SYNTAX_ERROR_LF                             ;#6182: C2 47 43
        ld      (MEGA_DISASM_CURSOR),de                        ;#6185: ED 53 5E EC
        inc     hl                                             ;#6189: 23
        call    PARSE_HEX_WORD_AND_EOL                         ;#618A: CD E1 43
        ld      (MEGA_AUTO_LINE_INCREMENT),de                  ;#618D: ED 53 16 EC
MEGA_PCMD_L_PARSED_LOOP:
        ; After args parsed — disasm from cursor until address >= AUTO_LINE_INCREMENT
        call    DISASM_INIT_INSTRUCTION_STATE                  ;#6191: CD D2 61
        call    PRINT_DISASM_LINE_SIMPLE                       ;#6194: CD C5 61
        call    CHECK_USER_INTERRUPT                           ;#6197: CD 9D 42
        jr      c,MEGA_PCMD_L_DONE                             ;#619A: 38 17
        ld      a,(DISASM_SPECIAL_MATCH_FLAG)                  ;#619C: 3A 47 EC
        or      a                                              ;#619F: B7
        call    nz,PRINT_BLANK_DISASM_LINE                     ;#61A0: C4 BA 61
        ld      hl,(MEGA_AUTO_LINE_INCREMENT)                  ;#61A3: 2A 16 EC
        ld      de,(MEGA_DISASM_CURSOR)                        ;#61A6: ED 5B 5E EC
        ld      a,d                                            ;#61AA: 7A
        or      e                                              ;#61AB: B3
        jr      z,MEGA_PCMD_L_DONE                             ;#61AC: 28 05
        or      a                                              ;#61AE: B7
        sbc     hl,de                                          ;#61AF: ED 52
        jr      nc,MEGA_PCMD_L_PARSED_LOOP                     ;#61B1: 30 DE
MEGA_PCMD_L_DONE:
        ; Exit path — snapshot MEGA_DISASM_CURSOR into MEGA_DISASM_LAST_END for next L
        ld      hl,(MEGA_DISASM_CURSOR)                        ;#61B3: 2A 5E EC
        ld      (MEGA_DISASM_LAST_END),hl                      ;#61B6: 22 45 EC
        ret                                                    ;#61B9: C9

PRINT_BLANK_DISASM_LINE:
        ; Clear line, place ';\r' at operand column, fall into PRINT_DISASM_LINE_SIMPLE
        call    DISASM_CLEAR_LINE                              ;#61BA: CD 4B 64
        ld      hl,MEGA_DISASM_OPERAND_COL                     ;#61BD: 21 D1 EC
        ld      (hl),";"                                       ;#61C0: 36 3B
        inc     hl                                             ;#61C2: 23
        ld      (hl),"\r"                                      ;#61C3: 36 0D
PRINT_DISASM_LINE_SIMPLE:
        ; Walk MEGA_DISASM_LINE through PRINT_CHAR_DUAL until CR — no paging logic
        ld      hl,MEGA_DISASM_LINE                            ;#61C5: 21 C3 EC
PRINT_DISASM_LINE_SIMPLE_LOOP:
        ; Per-char body: read (hl), PRINT_CHAR_DUAL, advance HL, loop until CR
        ld      a,(hl)                                         ;#61C8: 7E
        call    PRINT_CHAR_DUAL                                ;#61C9: CD C4 42
        inc     hl                                             ;#61CC: 23
        cp      0Dh                                            ;#61CD: FE 0D
        jr      nz,PRINT_DISASM_LINE_SIMPLE_LOOP               ;#61CF: 20 F7
        ret                                                    ;#61D1: C9

DISASM_INIT_INSTRUCTION_STATE:
        ; Reset per-instruction scratch (EC55/EC47/EC57) and clear output line
        xor     a                                              ;#61D2: AF
        ld      (MEGA_ASM_OPC_FLAGS),a                         ;#61D3: 32 55 EC
        ld      (DISASM_SPECIAL_MATCH_FLAG),a                  ;#61D6: 32 47 EC
        ld      a,"-"                                          ;#61D9: 3E 2D
        ld      (MEGA_DISASM_OPCODE),a                         ;#61DB: 32 57 EC
        call    DISASM_CLEAR_LINE                              ;#61DE: CD 4B 64
DISASM_INSTRUCTION:
        ; Disasm one instruction at MEGA_DISASM_CURSOR; dispatches on CB/ED/DD/FD prefix
        ld      hl,(MEGA_DISASM_CURSOR)                        ;#61E1: 2A 5E EC
        ld      (MEGA_DISASM_INSTR_START),hl                   ;#61E4: 22 60 EC
        ld      a,h                                            ;#61E7: 7C
        call    DISASM_EMIT_HEX_BYTE                           ;#61E8: CD 31 64
        ld      a,l                                            ;#61EB: 7D
        call    DISASM_EMIT_HEX_BYTE                           ;#61EC: CD 31 64
        call    READ_NEXT_USER_BYTE                            ;#61EF: CD C2 41
        cp      Z80_CB_PREFIX                                  ;#61F2: FE CB
        jr      z,DISASM_CB_PREFIX                             ;#61F4: 28 11
        cp      Z80_ED_PREFIX                                  ;#61F6: FE ED
        jr      z,DISASM_ED_PREFIX                             ;#61F8: 28 15
        cp      Z80_DD_PREFIX                                  ;#61FA: FE DD
        jr      z,DISASM_DD_PREFIX                             ;#61FC: 28 1C
        cp      Z80_FD_PREFIX                                  ;#61FE: FE FD
        jr      z,DISASM_FD_PREFIX                             ;#6200: 28 1B
        call    DISASM_SPECIAL_DISPATCH                        ;#6202: CD 10 63
        jr      DISASM_DDFD_TAIL_MAIN                          ;#6205: 18 30

DISASM_CB_PREFIX:
        ; CB-prefix dispatch: read next byte, look it up in DISASM_TABLE_CB
        call    READ_NEXT_USER_BYTE                            ;#6207: CD C2 41
        ld      hl,DISASM_TABLE_CB                             ;#620A: 21 EB 65
        jr      DISASM_LOOKUP_AND_EMIT                         ;#620D: 18 2B

DISASM_ED_PREFIX:
        ; ED-prefix dispatch: read next byte, RETN/RETI check, lookup in DISASM_TABLE_ED
        call    READ_NEXT_USER_BYTE                            ;#620F: CD C2 41
        call    DISASM_CHECK_ED_RET                            ;#6212: CD 24 63
        ld      hl,DISASM_TABLE_ED                             ;#6215: 21 27 66
        jr      DISASM_LOOKUP_AND_EMIT                         ;#6218: 18 20

DISASM_DD_PREFIX:
        ; DD-prefix entry — sets A=ID_OPERAND_IX (16h), falls into overlapping `ld bc,...`
        ; DD/FD prefix dispatch. 621A entry = DD (A loaded with 16h = ID_OPERAND_IX);
        ; 621D entry = FD (A loaded with 18h = ID_OPERAND_IY) via the overlapping
        ; `ld a,nn` / `ld bc,nnnn` trick at 621A-621E (see OVERLAP_LD_DE family). After
        ; stashing the index-register tag in MEGA_ASM_OPC_FLAGS and reading the next
        ; user byte, a DDCB/FDCB prefix branches to 625Ch; otherwise a cpir scans the
        ; 39-byte DISASM_HL_OPCODES table at 66B9 to validate the byte. Only opcodes
        ; that touch HL or (HL) — and only documented ones, so DD-prefixed LD H,r /
        ; LD L,r (60-65, 67-6D, 6F) are deliberately excluded — qualify for a DD/FD
        ; prefix. A miss falls to 6244h, which rewinds MEGA_DISASM_CURSOR and emits
        ; the prefix byte as a literal DEFB. A hit calls DISASM_CHECK_JP_HL (flags
        ; E9 as the JP IX / JP IY special case) and then dispatches through
        ; DISASM_TABLE_MAIN with the validated opcode in A.
        ld      a,ID_OPERAND_IX                                ;#621A: 3E 16
        OVERLAP_LD_BC                                          ;#621C: 01
DISASM_FD_PREFIX:
        ; FD-prefix entry — alt entry into DD overlap; runs `ld a,18h` (ID_OPERAND_IY)
        ld      a,ID_OPERAND_IY                                ;#621D: 3E 18
        ld      (MEGA_ASM_OPC_FLAGS),a                         ;#621F: 32 55 EC
        call    READ_NEXT_USER_BYTE                            ;#6222: CD C2 41
        cp      Z80_CB_PREFIX                                  ;#6225: FE CB
        jr      z,DISASM_DDFD_CB                               ;#6227: 28 33
        ld      bc,27h                                         ;#6229: 01 27 00
        ld      hl,DISASM_HL_OPCODES                           ;#622C: 21 B9 66
        cpir                                                   ;#622F: ED B1
        jr      nz,DISASM_DEFB_FALLBACK                        ;#6231: 20 11
        ld      c,a                                            ;#6233: 4F
        call    DISASM_CHECK_JP_HL                             ;#6234: CD 1F 63
DISASM_DDFD_TAIL_MAIN:
        ; Setup HL=main table for DDFD lookup tail
        ld      hl,DISASM_TABLE_MAIN                           ;#6237: 21 D8 64
DISASM_LOOKUP_AND_EMIT:
        ; Tail: DISASM_LOOKUP_TABLE on HL, then DISASM_EMIT_OPERANDS, jr to FINISH_LINE
        call    DISASM_LOOKUP_TABLE                            ;#623A: CD E0 62
        jr      c,DISASM_DEFB_FALLBACK                         ;#623D: 38 05
        call    DISASM_EMIT_OPERANDS                           ;#623F: CD 9E 62
        jr      DISASM_FINISH_LINE                             ;#6242: 18 3C

DISASM_DEFB_FALLBACK:
        ; Cpir-miss / lookup-fail: rewind cursor, emit one DEFB byte literal
        ld      hl,DISASM_INVALID_OPERAND_STR                  ;#6244: 21 E0 66
        call    DISASM_EMIT_TO_OPERAND_COL                     ;#6247: CD 23 64
        ld      iy,MEGA_DISASM_HEX_END_FAIL                    ;#624A: FD 21 D6 EC
        ld      hl,(MEGA_DISASM_INSTR_START)                   ;#624E: 2A 60 EC
        ld      (MEGA_DISASM_CURSOR),hl                        ;#6251: 22 5E EC
        call    READ_NEXT_USER_BYTE                            ;#6254: CD C2 41
        call    DISASM_EMIT_HEX_BYTE_H                         ;#6257: CD 48 63
        jr      DISASM_FINISH_LINE                             ;#625A: 18 24

DISASM_DDFD_CB:
        ; DDCB/FDCB handler: read displacement+opcode, r-field must=6, lookup in CB table
        call    READ_NEXT_USER_BYTE                            ;#625C: CD C2 41
        call    READ_NEXT_USER_BYTE                            ;#625F: CD C2 41
        and     7                                              ;#6262: E6 07
        cp      6                                              ;#6264: FE 06
        jr      nz,DISASM_DEFB_FALLBACK                        ;#6266: 20 DC
        ld      hl,DISASM_TABLE_CB                             ;#6268: 21 EB 65
        call    DISASM_LOOKUP_TABLE                            ;#626B: CD E0 62
        jr      c,DISASM_DEFB_FALLBACK                         ;#626E: 38 D4
        ld      de,(MEGA_DISASM_INSTR_START)                   ;#6270: ED 5B 60 EC
        inc     de                                             ;#6274: 13
        inc     de                                             ;#6275: 13
        ld      (MEGA_DISASM_CURSOR),de                        ;#6276: ED 53 5E EC
        call    DISASM_EMIT_OPERANDS                           ;#627A: CD 9E 62
        call    READ_NEXT_USER_BYTE                            ;#627D: CD C2 41
DISASM_FINISH_LINE:
        ; Emit CR, then walk MEGA_DISASM_CURSOR backwards printing the byte-dump column
        call    DISASM_EMIT_CR                                 ;#6280: CD 47 64
        ld      de,(MEGA_DISASM_CURSOR)                        ;#6283: ED 5B 5E EC
        ld      hl,(MEGA_DISASM_INSTR_START)                   ;#6287: 2A 60 EC
        ld      (MEGA_DISASM_CURSOR),hl                        ;#628A: 22 5E EC
        ld      iy,MEGA_DISASM_HEX_COL                         ;#628D: FD 21 C8 EC
DISASM_HEXDUMP_LOOP:
        ; Per-byte body: READ_NEXT_USER_BYTE then EMIT_HEX_BYTE until cursor matches end
        call    READ_NEXT_USER_BYTE                            ;#6291: CD C2 41
        call    DISASM_EMIT_HEX_BYTE                           ;#6294: CD 31 64
        ld      a,(MEGA_DISASM_CURSOR)                         ;#6297: 3A 5E EC
        cp      e                                              ;#629A: BB
        jr      nz,DISASM_HEXDUMP_LOOP                         ;#629B: 20 F4
        ret                                                    ;#629D: C9

DISASM_EMIT_OPERANDS:
        ; Save opcode in EC57, emit name to operand column, then dispatch operand encoder
        ld      e,a                                            ;#629E: 5F
        ld      (MEGA_DISASM_OPCODE),a                         ;#629F: 32 57 EC
        call    DISASM_EMIT_TO_OPERAND_COL                     ;#62A2: CD 23 64
        ld      a,e                                            ;#62A5: 7B
        and     3Fh                                            ;#62A6: E6 3F
        ret     z                                              ;#62A8: C8
        ld      d,0                                            ;#62A9: 16 00
        ld      iy,MEGA_DISASM_HEX_END_FAIL                    ;#62AB: FD 21 D6 EC
        ld      hl,DISASM_OPERAND_TABLE                        ;#62AF: 21 5B 64
        add     hl,de                                          ;#62B2: 19
        add     hl,de                                          ;#62B3: 19
        ld      e,(hl)                                         ;#62B4: 5E
        inc     hl                                             ;#62B5: 23
        ld      a,(hl)                                         ;#62B6: 7E
        push    af                                             ;#62B7: F5
        ld      a,e                                            ;#62B8: 7B
        call    DISASM_DISPATCH_OP_FN                          ;#62B9: CD C5 62
        pop     af                                             ;#62BC: F1
        cp      ";"                                            ;#62BD: FE 3B
        ret     z                                              ;#62BF: C8
        ld      d,","                                          ;#62C0: 16 2C
        call    DISASM_EMIT_D                                  ;#62C2: CD 2B 64
DISASM_DISPATCH_OP_FN:
        ; Computed jump into the per-operand OP_* handler at offset A in the table
        ld      hl,OP_NN                                       ;#62C5: 21 38 63
        cp      l                                              ;#62C8: BD
        ld      l,a                                            ;#62C9: 6F
        jr      nc,DISASM_DISPATCH_NO_CARRY                    ;#62CA: 30 01
        inc     h                                              ;#62CC: 24
DISASM_DISPATCH_NO_CARRY:
        ; Address-table offset >=L — increment H before jp (hl)
        ld      a,c                                            ;#62CD: 79
        rra                                                    ;#62CE: 1F
        rra                                                    ;#62CF: 1F
        rra                                                    ;#62D0: 1F
        and     7                                              ;#62D1: E6 07
        jp      (hl)                                           ;#62D3: E9

DISASM_FETCH_USER_BYTE_C:
        ; Fetch next byte at MEGA_DISASM_CURSOR into C (push/pop HL, advance cursor)
        push    hl                                             ;#62D4: E5
        ld      hl,(MEGA_DISASM_CURSOR)                        ;#62D5: 2A 5E EC
        ld      a,(hl)                                         ;#62D8: 7E
        inc     hl                                             ;#62D9: 23
        ld      (MEGA_DISASM_CURSOR),hl                        ;#62DA: 22 5E EC
        pop     hl                                             ;#62DD: E1
        ld      c,a                                            ;#62DE: 4F
        ret                                                    ;#62DF: C9

DISASM_LOOKUP_TABLE:
        ; Walk a DISASM_TABLE_* matching the opcode in C against the table at HL
        xor     a                                              ;#62E0: AF
        cp      (hl)                                           ;#62E1: BE
        jr      z,DISASM_LOOKUP_END_OK                         ;#62E2: 28 0D
        ld      a,c                                            ;#62E4: 79
        cp      (hl)                                           ;#62E5: BE
        inc     hl                                             ;#62E6: 23
        ld      a,0                                            ;#62E7: 3E 00
        ret     z                                              ;#62E9: C8
DISASM_LOOKUP_SKIP_NAME:
        ; Walk past the ASCII mnemonic name (bit-7 marker), then continue with next group
        bit     7,(hl)                                         ;#62EA: CB 7E
        inc     hl                                             ;#62EC: 23
        jr      z,DISASM_LOOKUP_SKIP_NAME                      ;#62ED: 28 FB
        jr      DISASM_LOOKUP_TABLE                            ;#62EF: 18 EF

DISASM_LOOKUP_END_OK:
        ; Group terminator (0 byte) — accept current opcode unmatched, fall to next
        inc     hl                                             ;#62F1: 23
DISASM_LOOKUP_RECORD:
        ; Per-record body: read mask/op/type triple; match if (opc&mask)==op
        ld      a,(hl)                                         ;#62F2: 7E
        inc     hl                                             ;#62F3: 23
        and     c                                              ;#62F4: A1
        cp      (hl)                                           ;#62F5: BE
        inc     hl                                             ;#62F6: 23
        ld      a,(hl)                                         ;#62F7: 7E
        inc     hl                                             ;#62F8: 23
        jr      z,DISASM_LOOKUP_TO_NAME                        ;#62F9: 28 0D
        bit     7,(hl)                                         ;#62FB: CB 7E
        jr      nz,DISASM_LOOKUP_RECORD                        ;#62FD: 20 F3
DISASM_LOOKUP_SKIP_NAME_INNER:
        ; Per-byte name skip inside a matched record — bit-7 ends
        ld      a,(hl)                                         ;#62FF: 7E
        add     a,a                                            ;#6300: 87
        inc     hl                                             ;#6301: 23
        jr      nc,DISASM_LOOKUP_SKIP_NAME_INNER               ;#6302: 30 FB
        bit     7,(hl)                                         ;#6304: CB 7E
        jr      nz,DISASM_LOOKUP_RECORD                        ;#6306: 20 EA
DISASM_LOOKUP_TO_NAME:
        ; After match: skip remaining DISASM records to bit-7-set (ASCII name start), ret
        bit     7,(hl)                                         ;#6308: CB 7E
        ret     z                                              ;#630A: C8
        inc     hl                                             ;#630B: 23
        inc     hl                                             ;#630C: 23
        inc     hl                                             ;#630D: 23
        jr      DISASM_LOOKUP_TO_NAME                          ;#630E: 18 F8

DISASM_SPECIAL_DISPATCH:
        ; cpir-search DISASM_SPECIAL_OPCODES; on hit, set EC47=FFh so the caller knows
        push    hl                                             ;#6310: E5
        push    bc                                             ;#6311: C5
        ld      hl,DISASM_SPECIAL_OPCODES                      ;#6312: 21 33 63
        ld      bc,5                                           ;#6315: 01 05 00
        cpir                                                   ;#6318: ED B1
        pop     bc                                             ;#631A: C1
        pop     hl                                             ;#631B: E1
        jr      z,DISASM_SET_SPECIAL_FLAG                      ;#631C: 28 0D
        ret                                                    ;#631E: C9

DISASM_CHECK_JP_HL:
        ; For DD/FD-prefixed E9 (JP IX / JP IY): set DISASM_SPECIAL_MATCH_FLAG
        cp      Z80_JP_HL                                      ;#631F: FE E9
        jr      z,DISASM_SET_SPECIAL_FLAG                      ;#6321: 28 08
        ret                                                    ;#6323: C9

DISASM_CHECK_ED_RET:
        ; For ED-prefix 45h (RETN) or 4Dh (RETI): set DISASM_SPECIAL_MATCH_FLAG
        cp      Z80_RETN                                       ;#6324: FE 45
        jr      z,DISASM_SET_SPECIAL_FLAG                      ;#6326: 28 03
        cp      Z80_RETI                                       ;#6328: FE 4D
        ret     nz                                             ;#632A: C0
DISASM_SET_SPECIAL_FLAG:
        ; Tail: push af; A=FFh; store at DISASM_SPECIAL_MATCH_FLAG; pop af; ret
        push    af                                             ;#632B: F5
        ld      a,0FFh                                         ;#632C: 3E FF
        ld      (DISASM_SPECIAL_MATCH_FLAG),a                  ;#632E: 32 47 EC
        pop     af                                             ;#6331: F1
        ret                                                    ;#6332: C9

DISASM_SPECIAL_OPCODES:
        ; 5-byte table for opcodes needing fetch of displacement/address operands
        ; Format: FORMAT_Z80_OPCODE_LIST
        ; - Like FORMAT_OPCODE_LIST but renders each byte through its Z80_-prefixed
        ; - equate in [values] when one exists (e.g. 18h → Z80_JR).
        db      Z80_JR                                         ;#6333: 18
        db      Z80_JP                                         ;#6334: C3
        db      Z80_HALT                                       ;#6335: 76
        db      Z80_RET                                        ;#6336: C9
        db      Z80_JP_HL                                      ;#6337: E9

OP_NN:
        ; Read 1 user byte, emit as `NNh` (immediate-byte operand encoder)
        call    READ_NEXT_USER_BYTE                            ;#6338: CD C2 41
OP_NONE:
        ; Tail: jr DISASM_EMIT_HEX_BYTE_H — also serves as "no operand" marker (3Bh)
        jr      DISASM_EMIT_HEX_BYTE_H                         ;#633B: 18 0B

OP_NNNN:
        ; Read 2 user bytes, emit as `NNNNh` (immediate-word operand encoder)
        call    READ_NEXT_USER_BYTE                            ;#633D: CD C2 41
        ld      b,a                                            ;#6340: 47
        call    READ_NEXT_USER_BYTE                            ;#6341: CD C2 41
OP_NNNN_EMIT_LOW:
        ; Emit low byte of word operand, fall to high byte
        call    DISASM_EMIT_HEX_BYTE                           ;#6344: CD 31 64
        ld      a,b                                            ;#6347: 78
DISASM_EMIT_HEX_BYTE_H:
        ; Emit A as 2 hex digits followed by 'H' suffix (Z80 hex literal syntax)
        call    DISASM_EMIT_HEX_BYTE                           ;#6348: CD 31 64
        ld      a,"H"                                          ;#634B: 3E 48
        jp      DISASM_EMIT_CHAR                               ;#634D: C3 41 64

OP_RST_VEC:
        ; Emit RST vector (bits 5-3 of opcode × 8 → hex) — RST 00..38h
        ld      a,c                                            ;#6350: 79
        and     38h                                            ;#6351: E6 38
        jr      DISASM_EMIT_HEX_BYTE_H                         ;#6353: 18 F3

OP_I_OR_R:
        ; Emit `I` or `R` register name (bit 3 of opcode picks)
        ld      a,"I"                                          ;#6355: 3E 49
        bit     3,c                                            ;#6357: CB 59
        jr      z,OP_I_OR_R_EMIT                               ;#6359: 28 02
        ld      a,"R"                                          ;#635B: 3E 52
OP_I_OR_R_EMIT:
        ; Tail jump to emit selected I/R char via trampoline
        jr      DISASM_EMIT_A_TRAMPOLINE                       ;#635D: 18 22

OP_NIBBLE:
        ; Emit low-nibble hex digit (used by IM and bit positions)
        jp      DISASM_EMIT_HEX_NIBBLE                         ;#635F: C3 3A 64

OP_DIGIT_0:
        ; Emit `'0'` (IM 0 / shift count 0 etc.)
        ld      a,"0"                                          ;#6362: 3E 30
        OVERLAP_LD_DE                                          ;#6364: 11
OP_DIGIT_1:
        ; Emit `'1'` (IM 1 / first form)
        ld      a,"1"                                          ;#6365: 3E 31
        OVERLAP_LD_DE                                          ;#6367: 11
OP_DIGIT_2:
        ; Emit `'2'` (IM 2)
        ld      a,"2"                                          ;#6368: 3E 32
        jr      DISASM_EMIT_A_TRAMPOLINE                       ;#636A: 18 15

OP_PAREN_RP:
        ; Emit `(rp)` — paren-wrapped register-pair indirect
        call    DISASM_EMIT_LPAREN                             ;#636C: CD 29 64
        call    OP_SP                                          ;#636F: CD 84 63
        jr      DISASM_EMIT_RPAREN                             ;#6372: 18 3F

OP_PAREN_R:
        ; Emit `(r)` — paren-wrapped r-table register
        call    DISASM_EMIT_LPAREN                             ;#6374: CD 29 64
        call    OP_R_MID                                       ;#6377: CD 9B 63
        jr      DISASM_EMIT_RPAREN                             ;#637A: 18 37

OP_AF_ALT:
        ; Emit `AF'` — alternate register set
        call    OP_AF                                          ;#637C: CD 87 63
        ld      a,"'"                                          ;#637F: 3E 27
DISASM_EMIT_A_TRAMPOLINE:
        ; 3-byte trampoline `jp DISASM_EMIT_CHAR` — used by handlers ending with `jr 6381`
        jp      DISASM_EMIT_CHAR                               ;#6381: C3 41 64

OP_SP:
        ; Emit literal `"SP"` register name
        ld      a,ID_OPERAND_SP                                ;#6384: 3E 0E
        OVERLAP_LD_DE                                          ;#6386: 11
OP_AF:
        ; Emit literal `"AF"` register name
        ld      a,ID_OPERAND_AF                                ;#6387: 3E 20
        OVERLAP_LD_DE                                          ;#6389: 11
OP_PAREN_C:
        ; Emit literal `"(C)"` — IN/OUT (C) addressing
        ld      a,ID_OPERAND_PAREN_C                           ;#638A: 3E 26
        OVERLAP_LD_DE                                          ;#638C: 11
OP_DE:
        ; Emit literal `"DE"` register name
        ld      a,ID_OPERAND_DE                                ;#638D: 3E 0A
        OVERLAP_LD_DE                                          ;#638F: 11
OP_HL:
        ; Emit literal `"HL"` register name
        ld      a,ID_OPERAND_HL                                ;#6390: 3E 0C
        OVERLAP_LD_DE                                          ;#6392: 11
OP_A:
        ; Emit literal `"A"` register name
        ld      a,ID_OPERAND_A                                 ;#6393: 3E 07
        jr      DISASM_EMIT_OP_NAME                            ;#6395: 18 77

OP_R_OR_HL:
        ; Like OP_R_MID but routes r=6 through OP_AF
        cp      6                                              ;#6397: FE 06
        jr      z,OP_AF                                        ;#6399: 28 EC
OP_R_MID:
        ; Emit r-table register from bits 5-3 of opcode (LD r,r' destination)
        and     3Eh                                            ;#639B: E6 3E
        add     a,8                                            ;#639D: C6 08
        cp      0Ch                                            ;#639F: FE 0C
        jr      nz,DISASM_EMIT_OP_NAME                         ;#63A1: 20 6B
DISASM_EMIT_RP_NAME:
OP_RP:
        ; Emit register-pair name (BC/DE/HL/SP or IX/IY) per MEGA_ASM_OPC_FLAGS+0Ch
        ld      a,(MEGA_ASM_OPC_FLAGS)                         ;#63A3: 3A 55 EC
        add     a,0Ch                                          ;#63A6: C6 0C
        jr      DISASM_EMIT_OP_NAME                            ;#63A8: 18 64

OP_PAREN_NN:
        ; Emit `(NNh)` — paren-wrapped immediate byte (IN/OUT NN)
        call    DISASM_EMIT_LPAREN                             ;#63AA: CD 29 64
        call    READ_NEXT_USER_BYTE                            ;#63AD: CD C2 41
OP_EMIT_BYTE_AND_RPAREN:
        ; Alt entry: emit existing A as hex+'H', fall into RPAREN — (IX+d) form
        call    DISASM_EMIT_HEX_BYTE_H                         ;#63B0: CD 48 63
DISASM_EMIT_RPAREN:
        ; Emit ')' (29h) via DISASM_EMIT_CHAR — common close-paren tail
        ld      a,")"                                          ;#63B3: 3E 29
        jr      DISASM_EMIT_A_TRAMPOLINE                       ;#63B5: 18 CA

OP_PAREN_NNNN:
        ; Emit `(NNNNh)` — paren-wrapped immediate word (LD A,(nnnn) etc.)
        call    DISASM_EMIT_LPAREN                             ;#63B7: CD 29 64
        push    bc                                             ;#63BA: C5
        call    OP_NNNN                                        ;#63BB: CD 3D 63
        pop     bc                                             ;#63BE: C1
        jr      DISASM_EMIT_RPAREN                             ;#63BF: 18 F2

OP_PAREN_RP_FLAGS:
        ; Emit `(rp)` using RP from flags — paren-wrapped (IX+d) etc.
        call    DISASM_EMIT_LPAREN                             ;#63C1: CD 29 64
        call    DISASM_EMIT_RP_NAME                            ;#63C4: CD A3 63
        jr      DISASM_EMIT_RPAREN                             ;#63C7: 18 EA

OP_IM_MODE:
        ; Emit IM-mode digit (mask bits 0-1 of opcode → 0/1/2)
        and     3                                              ;#63C9: E6 03
OP_BIT_INDEX:
        ; Emit bit-position digit (0-7) for BIT/RES/SET (bits 5-3 of opcode)
        add     a,a                                            ;#63CB: 87
        add     a,10h                                          ;#63CC: C6 10
        jr      DISASM_EMIT_OP_NAME                            ;#63CE: 18 3E

OP_JR_TARGET:
        ; Emit JR/DJNZ relative-jump target as absolute hex address
        call    READ_NEXT_USER_BYTE                            ;#63D0: CD C2 41
        ld      a,(MEGA_DISASM_CURSOR)                         ;#63D3: 3A 5E EC
        add     a,c                                            ;#63D6: 81
        ld      b,a                                            ;#63D7: 47
        ld      a,(MEGA_DISASM_CURSOR_HI)                      ;#63D8: 3A 5F EC
        adc     a,0                                            ;#63DB: CE 00
        bit     7,c                                            ;#63DD: CB 79
        jr      z,OP_JR_TARGET_EMIT                            ;#63DF: 28 01
        dec     a                                              ;#63E1: 3D
OP_JR_TARGET_EMIT:
        ; After sign-extension: jp into OP_NNNN's mid-emit (DISASM_EMIT_HEX_BYTE at 6344)
        jp      OP_NNNN_EMIT_LOW                               ;#63E2: C3 44 63

OP_R_LOW:
        ; Emit r-table register from low 3 bits of opcode (LD r,r' source)
        ld      a,c                                            ;#63E5: 79
        and     7                                              ;#63E6: E6 07
OP_R_LOW_OR_PAREN:
        ; Like OP_R_LOW but routes r=6 through `(HL)`/`(IX+d)` form
        cp      6                                              ;#63E8: FE 06
        jr      nz,DISASM_EMIT_OP_NAME                         ;#63EA: 20 22
        call    DISASM_EMIT_LPAREN                             ;#63EC: CD 29 64
        call    DISASM_EMIT_RP_NAME                            ;#63EF: CD A3 63
        ld      a,(MEGA_ASM_OPC_FLAGS)                         ;#63F2: 3A 55 EC
        or      a                                              ;#63F5: B7
        jr      z,DISASM_EMIT_RPAREN                           ;#63F6: 28 BB
        push    bc                                             ;#63F8: C5
        call    READ_NEXT_USER_BYTE                            ;#63F9: CD C2 41
        pop     bc                                             ;#63FC: C1
        or      a                                              ;#63FD: B7
        jr      z,DISASM_EMIT_RPAREN                           ;#63FE: 28 B3
        ld      d,"+"                                          ;#6400: 16 2B
        jp      p,OP_DISP_PLUS_EMIT                            ;#6402: F2 09 64
        ld      d,"-"                                          ;#6405: 16 2D
        neg                                                    ;#6407: ED 44
OP_DISP_PLUS_EMIT:
        ; Common arm — emit '+' or '-' then fall into byte-and-rparen emit
        call    DISASM_EMIT_D                                  ;#6409: CD 2B 64
        jr      OP_EMIT_BYTE_AND_RPAREN                        ;#640C: 18 A2

DISASM_EMIT_OP_NAME:
        ; Emit a name from DISASM_OPERAND_NAMES at offset A — bit-7-terminated walk
        ld      hl,DISASM_OPERAND_NAMES                        ;#640E: 21 AF 64
        add     a,l                                            ;#6411: 85
        ld      l,a                                            ;#6412: 6F
        jr      nc,DISASM_EMIT_NAME_LOOP                       ;#6413: 30 01
        inc     h                                              ;#6415: 24
DISASM_EMIT_NAME_LOOP:
        ; Per-char loop body: read+mask, emit if not space, ret on bit-7-set terminator
        ld      a,(hl)                                         ;#6416: 7E
        and     7Fh                                            ;#6417: E6 7F
        cp      " "                                            ;#6419: FE 20
        call    nz,DISASM_EMIT_CHAR                            ;#641B: C4 41 64
        cp      (hl)                                           ;#641E: BE
        ret     m                                              ;#641F: F8
        inc     hl                                             ;#6420: 23
        jr      DISASM_EMIT_NAME_LOOP                          ;#6421: 18 F3

DISASM_EMIT_TO_OPERAND_COL:
        ; Reset iy=ECD1 (operand column) and emit bit-7-terminated string from HL
        ld      iy,MEGA_DISASM_OPERAND_COL                     ;#6423: FD 21 D1 EC
        jr      DISASM_EMIT_NAME_LOOP                          ;#6427: 18 ED

DISASM_EMIT_LPAREN:
        ; Write '(' (28h) to (iy)++ — opens an addressing-mode parenthesis
        ld      d,"("                                          ;#6429: 16 28
DISASM_EMIT_D:
        ; Write D to (iy)++ — variant of DISASM_EMIT_CHAR used after a `ld d,X` setup
        ld      (iy),d                                         ;#642B: FD 72 00
        inc     iy                                             ;#642E: FD 23
        ret                                                    ;#6430: C9

DISASM_EMIT_HEX_BYTE:
        ; Convert A to two hex digits and write them to (iy)..(iy+1), advance iy by 2
        push    af                                             ;#6431: F5
        rrca                                                   ;#6432: 0F
        rrca                                                   ;#6433: 0F
        rrca                                                   ;#6434: 0F
        rrca                                                   ;#6435: 0F
        call    DISASM_EMIT_HEX_NIBBLE                         ;#6436: CD 3A 64
        pop     af                                             ;#6439: F1
DISASM_EMIT_HEX_NIBBLE:
        ; Convert low 4 bits of A to one hex digit and write to (iy)++ (DAA-trick encoder)
        and     0Fh                                            ;#643A: E6 0F
        cp      0Ah                                            ;#643C: FE 0A
        sbc     a,69h                                          ;#643E: DE 69
        daa                                                    ;#6440: 27
DISASM_EMIT_CHAR:
        ; Raw "write A to (iy)++" — basic byte emitter used by all higher-level wrappers
        ld      (iy),a                                         ;#6441: FD 77 00
        inc     iy                                             ;#6444: FD 23
        ret                                                    ;#6446: C9

DISASM_EMIT_CR:
        ; Write CR (0Dh) to (iy)++ — terminates the disasm line for screen output
        ld      a,"\r"                                         ;#6447: 3E 0D
        jr      DISASM_EMIT_CHAR                               ;#6449: 18 F6

DISASM_CLEAR_LINE:
        ; Fill MEGA_DISASM_LINE with 80 spaces, leaving iy at the start of the buffer
        ld      iy,MEGA_DISASM_LINE_END                        ;#644B: FD 21 13 ED
        ld      a,50h                                          ;#644F: 3E 50
DISASM_CLEAR_LINE_LOOP:
        ; Per-byte body: dec iy, store ' ' in 80 bytes (predec form)
        dec     iy                                             ;#6451: FD 2B
        ld      (iy),20h                                       ;#6453: FD 36 00 20
        dec     a                                              ;#6457: 3D
        jr      nz,DISASM_CLEAR_LINE_LOOP                      ;#6458: 20 F7
        ret                                                    ;#645A: C9

DISASM_OPERAND_TABLE:
        ; 42 (op1, op2) dispatch pairs indexed by opcode low 6 bits (62A2 dispatcher)
        ; DISASM_OPERAND_TABLE. The dispatcher at 62A2 (DISASM_EMIT_OPERANDS)
        ; masks the opcode to its low 6 bits, ignores 0, and uses 1..3Fh as an
        ; index into a 2-byte-per-entry table here. Each entry holds
        ; `(op1_dispatch, op2_dispatch)`: byte values 0..37h jump to 64xx-area
        ; encoders (handled by 62C5 via `HL=6400+byte`), and bytes 38h..FFh
        ; jump to 63xx-area encoders (`HL=6300+byte`). The second byte is
        ; consumed only if it is not 3Bh (`';'` = "no second operand"); when
        ; present, a `','` (2Ch) separator is emitted first via DISASM_EMIT_D.
        ; The dispatch byte's numeric value is literally the low byte of the
        ; handler's address, so a tag like `93h` jumps to the routine at 6393h.
        ;
        ; The table occupies 645Bh..64AEh (42 × 2 = 84 bytes). The bytes that
        ; follow at 64AFh..64D7h are a separate name-fragment table walked by
        ; 640Eh for register/condition strings (`BC`, `DE`, `HL`, `SP`, `AF`,
        ; `NZ`/`Z`/`NC`/`C`, `M`, `P`, `(C)`, …), not part of the operand
        ; dispatch.
        ; Format: FORMAT_BYTE_PAIRS
        ; - Used by DISASM_OPERAND_TABLE: each entry is (operand_char, encoding_byte).
        db      low OP_NONE, low OP_NONE                       ;#645B: 3B 3B
        db      low OP_R_LOW, low OP_NONE                      ;#645D: E5 3B
        db      low OP_R_LOW_OR_PAREN, low OP_PAREN_C          ;#645F: E8 8A
        db      low OP_PAREN_C, low OP_R_LOW_OR_PAREN          ;#6461: 8A E8
        db      low OP_R_MID, low OP_NONE                      ;#6463: 9B 3B
        db      low OP_NIBBLE, low OP_R_LOW                    ;#6465: 5F E5
        db      low OP_R_LOW_OR_PAREN, low OP_NONE             ;#6467: E8 3B
        db      low OP_HL, low OP_R_MID                        ;#6469: 90 9B
        db      low OP_RP, low OP_R_MID                        ;#646B: A3 9B
        db      low OP_R_LOW_OR_PAREN, low OP_R_LOW            ;#646D: E8 E5
        db      low OP_AF, low OP_AF_ALT                       ;#646F: 87 7C
        db      low OP_RST_VEC, low OP_NONE                    ;#6471: 50 3B
        db      low OP_A, low OP_R_LOW                         ;#6473: 93 E5
        db      low OP_DIGIT_0, low OP_NONE                    ;#6475: 62 3B
        db      low OP_DIGIT_1, low OP_NONE                    ;#6477: 65 3B
        db      low OP_DIGIT_2, low OP_NONE                    ;#6479: 68 3B
        db      low OP_SP, low OP_RP                           ;#647B: 84 A3
        db      low OP_PAREN_R, low OP_A                       ;#647D: 74 93
        db      low OP_A, low OP_PAREN_R                       ;#647F: 93 74
        db      low OP_A, low OP_I_OR_R                        ;#6481: 93 55
        db      low OP_I_OR_R, low OP_A                        ;#6483: 55 93
        db      low OP_PAREN_RP_FLAGS, low OP_NONE             ;#6485: C1 3B
        db      low OP_R_OR_HL, low OP_NONE                    ;#6487: 97 3B
        db      low OP_BIT_INDEX, low OP_NONE                  ;#6489: CB 3B
        db      low OP_DE, low OP_HL                           ;#648B: 8D 90
        db      low OP_PAREN_RP, low OP_RP                     ;#648D: 6C A3
        db      low OP_A, low OP_PAREN_NN                      ;#648F: 93 AA
        db      low OP_PAREN_NN, low OP_A                      ;#6491: AA 93
        db      low OP_NN, low OP_NONE                         ;#6493: 38 3B
        db      low OP_A, low OP_NN                            ;#6495: 93 38
        db      low OP_R_LOW_OR_PAREN, low OP_NN               ;#6497: E8 38
        db      low OP_R_MID, low OP_NNNN                      ;#6499: 9B 3D
        db      low OP_IM_MODE, low OP_JR_TARGET               ;#649B: C9 D0
        db      low OP_JR_TARGET, low OP_NONE                  ;#649D: D0 3B
        db      low OP_BIT_INDEX, low OP_NNNN                  ;#649F: CB 3D
        db      low OP_NNNN, low OP_NONE                       ;#64A1: 3D 3B
        db      low OP_A, low OP_PAREN_NNNN                    ;#64A3: 93 B7
        db      low OP_PAREN_NNNN, low OP_A                    ;#64A5: B7 93
        db      low OP_RP, low OP_PAREN_NNNN                   ;#64A7: A3 B7
        db      low OP_PAREN_NNNN, low OP_RP                   ;#64A9: B7 A3
        db      low OP_R_MID, low OP_PAREN_NNNN                ;#64AB: 9B B7
        db      low OP_PAREN_NNNN, low OP_R_MID                ;#64AD: B7 9B

DISASM_OPERAND_NAMES:
        ; Name-fragment table walked by 640E for register/condition strings
        db      "B"C                                           ;#64AF: C2
        db      "C"C                                           ;#64B0: C3
        db      "D"C                                           ;#64B1: C4
        db      "E"C                                           ;#64B2: C5
        db      "H"C                                           ;#64B3: C8
        db      "L"C                                           ;#64B4: CC
        db      "M"C                                           ;#64B5: CD
        db      "A"C                                           ;#64B6: C1
        db      "BC"C                                          ;#64B7: 42 C3
        db      "DE"C                                          ;#64B9: 44 C5
        db      "HL"C                                          ;#64BB: 48 CC
        db      "SP"C                                          ;#64BD: 53 D0
        db      "NZ"C                                          ;#64BF: 4E DA
        db      "Z "C                                          ;#64C1: 5A A0
        db      "NC"C                                          ;#64C3: 4E C3
        db      "C "C                                          ;#64C5: 43 A0
        db      "PO"C                                          ;#64C7: 50 CF
        db      "PE"C                                          ;#64C9: 50 C5
        db      "P "C                                          ;#64CB: 50 A0
        db      "M "C                                          ;#64CD: 4D A0
        db      "AF"C                                          ;#64CF: 41 C6
        db      "IX"C                                          ;#64D1: 49 D8
        db      "IY"C                                          ;#64D3: 49 D9
        db      "(C)"C                                         ;#64D5: 28 43 A9

DISASM_TABLE_MAIN:
        ; Main disasm table — first 12 records are clean no-operand opcode+name
        ; Z80 mnemonic encoding tables. Each table contains records of the form
        ; `<opcode_byte> <name_bytes>` where the last byte of the name has bit 7
        ; set as the run terminator. The pre-name opcode byte holds the instruction
        ; encoding (for ED/CB prefixes, it is the byte AFTER the prefix). The
        ; lookup routines at 6215h+ point HL at the relevant table and walk
        ; records via the bit-7-terminated-name convention.
        DISASM_SIMPLE Z80_CCF, "CCF"C                          ;#64D8: 3F 43 43 C6
        DISASM_SIMPLE Z80_CPL, "CPL"C                          ;#64DC: 2F 43 50 CC
        DISASM_SIMPLE Z80_DAA, "DAA"C                          ;#64E0: 27 44 41 C1
        DISASM_SIMPLE Z80_DI, "DI"C                            ;#64E4: F3 44 C9
        DISASM_SIMPLE Z80_EI, "EI"C                            ;#64E7: FB 45 C9
        DISASM_SIMPLE Z80_EXX, "EXX"C                          ;#64EA: D9 45 58 D8
        DISASM_SIMPLE Z80_HALT, "HALT"C                        ;#64EE: 76 48 41 4C D4
        DISASM_SIMPLE Z80_RLA, "RLA"C                          ;#64F3: 17 52 4C C1
        DISASM_SIMPLE Z80_RLCA, "RLCA"C                        ;#64F7: 07 52 4C 43 C1
        DISASM_SIMPLE Z80_RRA, "RRA"C                          ;#64FC: 1F 52 52 C1
        DISASM_SIMPLE Z80_RRCA, "RRCA"C                        ;#6500: 0F 52 52 43 C1
        DISASM_SIMPLE Z80_SCF, "SCF"C                          ;#6505: 37 53 43 C6
        db      0                                              ;#6509: 00
        DISASM mask=0FFh, op=Z80_LD_HL_PAREN_NN, type=ID_RP_PAREN_NN  ;#650A: FF 2A 26
        DISASM mask=0FFh, op=Z80_LD_PAREN_NN_HL, type=ID_PAREN_NN_RP  ;#650D: FF 22 27
        DISASM mask=0FFh, op=Z80_LD_A_PAREN_NN, type=ID_A_PAREN_NN  ;#6510: FF 3A 24
        DISASM mask=0FFh, op=Z80_LD_PAREN_NN_A, type=ID_PAREN_NN_A  ;#6513: FF 32 25
        DISASM mask=0FFh, op=Z80_LD_SP_HL, type=ID_SP_HL       ;#6516: FF F9 10
        DISASM mask=0EFh, op=Z80_LD_PAREN_BC_A, type=ID_PAREN_R_A  ;#6519: EF 02 11
        DISASM mask=0EFh, op=Z80_LD_A_PAREN_BC, type=ID_A_PAREN_R  ;#651C: EF 0A 12
        DISASM mask=0C0h, op=Z80_LD_R_R, type=ID_R_R           ;#651F: C0 40 09
        DISASM mask=0C7h, op=Z80_LD_R_N, type=ID_R_N           ;#6522: C7 06 1E
        DISASM mask=0CFh, op=Z80_LD_RP_NN, type=ID_RP_NN       ;#6525: CF 01 1F
        db      "LD"C                                          ;#6528: 4C C4
        DISASM mask=0FFh, op=Z80_ADC_A_N, type=ID_A_N          ;#652A: FF CE 1D
        DISASM mask=0F8h, op=Z80_ADC_A_R, type=ID_A_R          ;#652D: F8 88 0C
        db      "ADC"C                                         ;#6530: 41 44 C3
        DISASM mask=0FFh, op=Z80_ADD_A_N, type=ID_A_N          ;#6533: FF C6 1D
        DISASM mask=0F8h, op=Z80_ADD_A_R, type=ID_A_R          ;#6536: F8 80 0C
        DISASM mask=0CFh, op=Z80_ADD_HL_RP, type=ID_RP_R_MID   ;#6539: CF 09 08
        db      "ADD"C                                         ;#653C: 41 44 C4
        DISASM mask=0FFh, op=Z80_AND_N, type=ID_N              ;#653F: FF E6 1C
        DISASM mask=0F8h, op=Z80_AND_R, type=ID_R_LOW          ;#6542: F8 A0 01
        db      "AND"C                                         ;#6545: 41 4E C4
        DISASM mask=0FFh, op=Z80_CALL, type=ID_NN              ;#6548: FF CD 23
        DISASM mask=0C7h, op=Z80_CALL_CC, type=ID_CC_NN        ;#654B: C7 C4 22
        db      "CALL"C                                        ;#654E: 43 41 4C CC
        DISASM mask=0FFh, op=Z80_CP_N, type=ID_N               ;#6552: FF FE 1C
        DISASM mask=0F8h, op=Z80_CP_R, type=ID_R_LOW           ;#6555: F8 B8 01
        db      "CP"C                                          ;#6558: 43 D0
        DISASM mask=0C7h, op=Z80_DEC_R, type=ID_R_HL_LOW       ;#655A: C7 05 06
        DISASM mask=0CFh, op=Z80_DEC_RP, type=ID_R_MID         ;#655D: CF 0B 04
        db      "DEC"C                                         ;#6560: 44 45 C3
        DISASM mask=0FFh, op=Z80_DJNZ, type=ID_E               ;#6563: FF 10 21
        db      "DJNZ"C                                        ;#6566: 44 4A 4E DA
        DISASM mask=0FFh, op=Z80_EX_DE_HL, type=ID_DE_HL       ;#656A: FF EB 18
        DISASM mask=0FFh, op=Z80_EX_SP_HL, type=ID_PAREN_SP_HL  ;#656D: FF E3 19
        DISASM mask=0FFh, op=Z80_EX_AF_AF, type=ID_AF_AF       ;#6570: FF 08 0A
        db      "EX"C                                          ;#6573: 45 D8
        DISASM mask=0FFh, op=Z80_IN_A_N, type=ID_A_PAREN_N     ;#6575: FF DB 1A
        db      "IN"C                                          ;#6578: 49 CE
        DISASM mask=0C7h, op=Z80_INC_R, type=ID_R_HL_LOW       ;#657A: C7 04 06
        DISASM mask=0CFh, op=Z80_INC_RP, type=ID_R_MID         ;#657D: CF 03 04
        db      "INC"C                                         ;#6580: 49 4E C3
        DISASM mask=0C7h, op=Z80_JP_CC, type=ID_CC_NN          ;#6583: C7 C2 22
        DISASM mask=0FFh, op=Z80_JP, type=ID_NN                ;#6586: FF C3 23
        DISASM mask=0FFh, op=Z80_JP_HL, type=ID_PAREN_HL       ;#6589: FF E9 15
        db      "JP"C                                          ;#658C: 4A D0
        DISASM mask=0FFh, op=Z80_JR, type=ID_E                 ;#658E: FF 18 21
        DISASM mask=0E7h, op=Z80_JR_CC, type=ID_CC_E           ;#6591: E7 20 20
        db      "JR"C                                          ;#6594: 4A D2
        DISASM mask=0FFh, op=Z80_OUT_N_A, type=ID_PAREN_N_A    ;#6596: FF D3 1B
        db      "OUT"C                                         ;#6599: 4F 55 D4
        DISASM mask=0FFh, op=Z80_NOP, type=ID_NONE             ;#659C: FF 00 00
        db      "NOP"C                                         ;#659F: 4E 4F D0
        DISASM mask=0FFh, op=Z80_OR_N, type=ID_N               ;#65A2: FF F6 1C
        DISASM mask=0F8h, op=Z80_OR_R, type=ID_R_LOW           ;#65A5: F8 B0 01
        db      "OR"C                                          ;#65A8: 4F D2
        DISASM mask=0CFh, op=Z80_POP_RP, type=ID_RP_STACK      ;#65AA: CF C1 16
        db      "POP"C                                         ;#65AD: 50 4F D0
        DISASM mask=0CFh, op=Z80_PUSH_RP, type=ID_RP_STACK     ;#65B0: CF C5 16
        db      "PUSH"C                                        ;#65B3: 50 55 53 C8
        DISASM mask=0FFh, op=Z80_RET, type=ID_NONE             ;#65B7: FF C9 00
        DISASM mask=0C7h, op=Z80_RET_CC, type=ID_RET_CC        ;#65BA: C7 C0 17
        db      "RET"C                                         ;#65BD: 52 45 D4
        DISASM mask=0C7h, op=Z80_RST, type=ID_RST              ;#65C0: C7 C7 0B
        db      "RST"C                                         ;#65C3: 52 53 D4
        DISASM mask=0FFh, op=Z80_SBC_A_N, type=ID_A_N          ;#65C6: FF DE 1D
        DISASM mask=0F8h, op=Z80_SBC_A_R, type=ID_A_R          ;#65C9: F8 98 0C
        db      "SBC"C                                         ;#65CC: 53 42 C3
        DISASM mask=0FFh, op=Z80_SUB_N, type=ID_N              ;#65CF: FF D6 1C
        DISASM mask=0F8h, op=Z80_SUB_R, type=ID_R_LOW          ;#65D2: F8 90 01
        db      "SUB"C                                         ;#65D5: 53 55 C2
        DISASM mask=0FFh, op=Z80_XOR_N, type=ID_N              ;#65D8: FF EE 1C
        DISASM mask=0F8h, op=Z80_XOR_R, type=ID_R_LOW          ;#65DB: F8 A8 01
        db      "XOR"C                                         ;#65DE: 58 4F D2
        db      0                                              ;#65E1: 00

TINY_SOFT:
        ; "TinySoft" reversed-ASCII easter egg between the main and CB tables
        ; Format: FORMAT_RAW_STRING
        ; - For embedded text that isn't 0-terminated or bit-7-terminated.
        db      "tfoS yniT"                                    ;#65E2: 74 66 6F 53 20 79 6E 69 54

DISASM_TABLE_CB:
        ; Z80 mnemonic table — CB-prefix instructions (BIT, RES, SET, RL, RR, ...)
        ; Format: FORMAT_OPCODE_LIST
        ; - Used by cpir-search tables — each byte is a 1-byte instruction opcode.
        db      0                                              ;#65EB: 00
        DISASM mask=0C0h, op=Z80_BIT_BASE, type=ID_BIT_R       ;#65EC: C0 40 05
        db      "BIT"C                                         ;#65EF: 42 49 D4
        DISASM mask=0C0h, op=Z80_RES_BASE, type=ID_BIT_R       ;#65F2: C0 80 05
        db      "RES"C                                         ;#65F5: 52 45 D3
        DISASM mask=0C0h, op=Z80_SET_BASE, type=ID_BIT_R       ;#65F8: C0 C0 05
        db      "SET"C                                         ;#65FB: 53 45 D4
        DISASM mask=0F8h, op=Z80_RL_BASE, type=ID_R_LOW        ;#65FE: F8 10 01
        db      "RL"C                                          ;#6601: 52 CC
        DISASM mask=0F8h, op=Z80_RR_BASE, type=ID_R_LOW        ;#6603: F8 18 01
        db      "RR"C                                          ;#6606: 52 D2
        DISASM mask=0F8h, op=Z80_RLC_BASE, type=ID_R_LOW       ;#6608: F8 00 01
        db      "RLC"C                                         ;#660B: 52 4C C3
        DISASM mask=0F8h, op=Z80_RRC_BASE, type=ID_R_LOW       ;#660E: F8 08 01
        db      "RRC"C                                         ;#6611: 52 52 C3
        DISASM mask=0F8h, op=Z80_SLA_BASE, type=ID_R_LOW       ;#6614: F8 20 01
        db      "SLA"C                                         ;#6617: 53 4C C1
        DISASM mask=0F8h, op=Z80_SRA_BASE, type=ID_R_LOW       ;#661A: F8 28 01
        db      "SRA"C                                         ;#661D: 53 52 C1
        DISASM mask=0F8h, op=Z80_SRL_BASE, type=ID_R_LOW       ;#6620: F8 38 01
        db      "SRL"C                                         ;#6623: 53 52 CC

DISASM_CB_END:
        ; CB-table terminator byte (00)
        db      0                                              ;#6626: 00

DISASM_TABLE_ED:
        ; Disasm table for ED-prefix; first 21 records are clean opcode + "name"C
        DISASM_SIMPLE Z80_CPD, "CPD"C                          ;#6627: A9 43 50 C4
        DISASM_SIMPLE Z80_CPDR, "CPDR"C                        ;#662B: B9 43 50 44 D2
        DISASM_SIMPLE Z80_CPI, "CPI"C                          ;#6630: A1 43 50 C9
        DISASM_SIMPLE Z80_CPIR, "CPIR"C                        ;#6634: B1 43 50 49 D2
        DISASM_SIMPLE Z80_IND, "IND"C                          ;#6639: AA 49 4E C4
        DISASM_SIMPLE Z80_INDR, "INDR"C                        ;#663D: BA 49 4E 44 D2
        DISASM_SIMPLE Z80_INI, "INI"C                          ;#6642: A2 49 4E C9
        DISASM_SIMPLE Z80_INIR, "INIR"C                        ;#6646: B2 49 4E 49 D2
        DISASM_SIMPLE Z80_LDD, "LDD"C                          ;#664B: A8 4C 44 C4
        DISASM_SIMPLE Z80_LDDR, "LDDR"C                        ;#664F: B8 4C 44 44 D2
        DISASM_SIMPLE Z80_LDI, "LDI"C                          ;#6654: A0 4C 44 C9
        DISASM_SIMPLE Z80_LDIR, "LDIR"C                        ;#6658: B0 4C 44 49 D2
        DISASM_SIMPLE Z80_NEG, "NEG"C                          ;#665D: 44 4E 45 C7
        DISASM_SIMPLE Z80_OTDR, "OTDR"C                        ;#6661: BB 4F 54 44 D2
        DISASM_SIMPLE Z80_OTIR, "OTIR"C                        ;#6666: B3 4F 54 49 D2
        DISASM_SIMPLE Z80_OUTD, "OUTD"C                        ;#666B: AB 4F 55 54 C4
        DISASM_SIMPLE Z80_OUTI, "OUTI"C                        ;#6670: A3 4F 55 54 C9
        DISASM_SIMPLE Z80_RETI, "RETI"C                        ;#6675: 4D 52 45 54 C9
        DISASM_SIMPLE Z80_RETN, "RETN"C                        ;#667A: 45 52 45 54 CE
        DISASM_SIMPLE Z80_RLD, "RLD"C                          ;#667F: 6F 52 4C C4
        DISASM_SIMPLE Z80_RRD, "RRD"C                          ;#6683: 67 52 52 C4
        db      0                                              ;#6687: 00
        DISASM mask=0CFh, op=Z80_ADC_HL_BASE, type=ID_HL_R_MID  ;#6688: CF 4A 07
        db      "ADC"C                                         ;#668B: 41 44 C3
        DISASM mask=0FFh, op=Z80_IM_0_OPC, type=ID_IM_0        ;#668E: FF 46 0D
        DISASM mask=0FFh, op=Z80_IM_1_OPC, type=ID_IM_1        ;#6691: FF 56 0E
        DISASM mask=0FFh, op=Z80_IM_2_OPC, type=ID_IM_2        ;#6694: FF 5E 0F
        db      "IM"C                                          ;#6697: 49 CD
        DISASM mask=0C7h, op=Z80_IN_R_C_BASE, type=ID_R_LOW_PAREN_C  ;#6699: C7 40 02
        db      "IN"C                                          ;#669C: 49 CE
        DISASM mask=0CFh, op=Z80_LD_RP_PNN_BASE, type=ID_RP_PAREN_NN_ED  ;#669E: CF 4B 28
        DISASM mask=0CFh, op=Z80_LD_PNN_RP_BASE, type=ID_PAREN_NN_RP_ED  ;#66A1: CF 43 29
        DISASM mask=0F7h, op=Z80_LD_A_IR_BASE, type=ID_A_IR    ;#66A4: F7 57 13
        DISASM mask=0F7h, op=Z80_LD_IR_A_BASE, type=ID_IR_A    ;#66A7: F7 47 14
        db      "LD"C                                          ;#66AA: 4C C4
        DISASM mask=0C7h, op=Z80_OUT_C_R_BASE, type=ID_PAREN_C_R_LOW  ;#66AC: C7 41 03
        db      "OUT"C                                         ;#66AF: 4F 55 D4
        DISASM mask=0CFh, op=Z80_SBC_HL_BASE, type=ID_HL_R_MID  ;#66B2: CF 42 07
        db      "SBC"C                                         ;#66B5: 53 42 C3
        db      0                                              ;#66B8: 00

DISASM_HL_OPCODES:
        ; 39 opcodes the disassembler accepts as DD/FD-prefixable (cpir gate at 622Fh)
        ; Format: FORMAT_Z80_OPCODE_LIST
        ; - Like FORMAT_OPCODE_LIST but renders each byte through its Z80_-prefixed
        ; - equate in [values] when one exists (e.g. 18h → Z80_JR).
        db      Z80_LD_HL_PAREN_NN                             ;#66B9: 2A
        db      Z80_LD_PAREN_HL_A                              ;#66BA: 77
        db      Z80_LD_A_PAREN_HL                              ;#66BB: 7E
        db      Z80_LD_HL_NN                                   ;#66BC: 21
        db      Z80_SUB_PAREN_HL                               ;#66BD: 96
        db      Z80_LD_PAREN_NN_HL                             ;#66BE: 22
        db      Z80_SBC_A_PAREN_HL                             ;#66BF: 9E
        db      Z80_ADD_HL_BC                                  ;#66C0: 09
        db      Z80_ADD_A_PAREN_HL                             ;#66C1: 86
        db      Z80_ADD_HL_DE                                  ;#66C2: 19
        db      Z80_ADC_A_PAREN_HL                             ;#66C3: 8E
        db      Z80_INC_HL                                     ;#66C4: 23
        db      Z80_AND_PAREN_HL                               ;#66C5: A6
        db      Z80_ADD_HL_HL                                  ;#66C6: 29
        db      Z80_XOR_PAREN_HL                               ;#66C7: AE
        db      Z80_INC_PAREN_HL                               ;#66C8: 34
        db      Z80_OR_PAREN_HL                                ;#66C9: B6
        db      Z80_DEC_PAREN_HL                               ;#66CA: 35
        db      Z80_CP_PAREN_HL                                ;#66CB: BE
        db      Z80_LD_PAREN_HL_N                              ;#66CC: 36
        db      Z80_DEC_HL                                     ;#66CD: 2B
        db      Z80_ADD_HL_SP                                  ;#66CE: 39
        db      Z80_POP_HL                                     ;#66CF: E1
        db      Z80_LD_B_PAREN_HL                              ;#66D0: 46
        db      Z80_EX_SP_HL                                   ;#66D1: E3
        db      Z80_LD_C_PAREN_HL                              ;#66D2: 4E
        db      Z80_PUSH_HL                                    ;#66D3: E5
        db      Z80_LD_D_PAREN_HL                              ;#66D4: 56
        db      Z80_JP_HL                                      ;#66D5: E9
        db      Z80_LD_E_PAREN_HL                              ;#66D6: 5E
        db      Z80_LD_SP_HL                                   ;#66D7: F9
        db      Z80_LD_H_PAREN_HL                              ;#66D8: 66
        db      Z80_LD_L_PAREN_HL                              ;#66D9: 6E
        db      Z80_LD_PAREN_HL_B                              ;#66DA: 70
        db      Z80_LD_PAREN_HL_C                              ;#66DB: 71
        db      Z80_LD_PAREN_HL_D                              ;#66DC: 72
        db      Z80_LD_PAREN_HL_E                              ;#66DD: 73
        db      Z80_LD_PAREN_HL_H                              ;#66DE: 74
        db      Z80_LD_PAREN_HL_L                              ;#66DF: 75

DISASM_INVALID_OPERAND_STR:
        ; Bit-7-terminated "?" string emitted as the operand-column fallback at 6244h
        db      "??"C                                          ;#66E0: 3F BF

RENDER_SCREEN_CELL_GFX:
        ; Build the 64-byte glyph row buffer for one screen cell, accounting for SCRMOD
        push    bc                                             ;#66E2: C5
        push    de                                             ;#66E3: D5
        push    hl                                             ;#66E4: E5
        push    iy                                             ;#66E5: FD E5
        ld      hl,MEGA_EDITOR_CELL_BUF                        ;#66E7: 21 3C FA
        ld      a,40h                                          ;#66EA: 3E 40
RENDER_CELL_CLEAR_LOOP:
        ; Zero the 64-byte MEGA_EDITOR_CELL_BUF before pixel fetch
        ld      (hl),0                                         ;#66EC: 36 00
        inc     hl                                             ;#66EE: 23
        dec     a                                              ;#66EF: 3D
        jr      nz,RENDER_CELL_CLEAR_LOOP                      ;#66F0: 20 FA
        ld      a,(BIOS_SCRMOD)                                ;#66F2: 3A AF FC
        or      a                                              ;#66F5: B7
        push    af                                             ;#66F6: F5
        push    bc                                             ;#66F7: C5
        call    nz,SPRITE_CELL_TO_PIXEL                        ;#66F8: C4 B4 67
        pop     bc                                             ;#66FB: C1
        ld      l,c                                            ;#66FC: 69
        ld      h,0                                            ;#66FD: 26 00
        add     hl,hl                                          ;#66FF: 29
        add     hl,hl                                          ;#6700: 29
        add     hl,hl                                          ;#6701: 29
        ld      e,l                                            ;#6702: 5D
        ld      d,h                                            ;#6703: 54
        add     hl,hl                                          ;#6704: 29
        add     hl,hl                                          ;#6705: 29
        pop     af                                             ;#6706: F1
        push    af                                             ;#6707: F5
        jr      nz,RENDER_CELL_TEXT_ADJUST                     ;#6708: 20 01
        add     hl,de                                          ;#670A: 19
RENDER_CELL_TEXT_ADJUST:
        ; SCRMOD==0 (text) arm — drop the secondary table add (only 1 column)
        ld      e,b                                            ;#670B: 58
        add     hl,de                                          ;#670C: 19
        ex      de,hl                                          ;#670D: EB
        sub     2                                              ;#670E: D6 02
        ld      a,c                                            ;#6710: 79
        ld      bc,0                                           ;#6711: 01 00 00
        ld      hl,(BIOS_CGPBAS)                               ;#6714: 2A 24 F9
        push    hl                                             ;#6717: E5
        ld      hl,(BIOS_NAMBAS)                               ;#6718: 2A 22 F9
        jr      c,RENDER_CELL_AFTER_TABLES                     ;#671B: 38 19
        jr      nz,RENDER_CELL_MULTICOLOR                      ;#671D: 20 0C
        ld      hl,(BIOS_GRPCGP)                               ;#671F: 2A CB F3
        ex      (sp),hl                                        ;#6722: E3
        ld      hl,(BIOS_GRPNAM)                               ;#6723: 2A C7 F3
        and     18h                                            ;#6726: E6 18
        ld      b,a                                            ;#6728: 47
        jr      RENDER_CELL_AFTER_TABLES                       ;#6729: 18 0B

RENDER_CELL_MULTICOLOR:
        ; SCREEN 3 (multicolor) arm — load MLTCGP/MLTNAM tables instead of GRPCGP/GRPNAM
        ld      hl,(BIOS_MLTCGP)                               ;#672B: 2A D5 F3
        ex      (sp),hl                                        ;#672E: E3
        ld      hl,(BIOS_MLTNAM)                               ;#672F: 2A D1 F3
        rlca                                                   ;#6732: 07
        and     6                                              ;#6733: E6 06
        ld      c,a                                            ;#6735: 4F
RENDER_CELL_AFTER_TABLES:
        ; Common tail after table selection — read VRAM byte, compute pattern address
        add     hl,de                                          ;#6736: 19
        call    BIOS_RDVRM                                     ;#6737: CD 4A 00
        ld      l,a                                            ;#673A: 6F
        ld      h,0                                            ;#673B: 26 00
        add     hl,hl                                          ;#673D: 29
        add     hl,hl                                          ;#673E: 29
        add     hl,hl                                          ;#673F: 29
        add     hl,bc                                          ;#6740: 09
        ex      de,hl                                          ;#6741: EB
        pop     iy                                             ;#6742: FD E1
        add     iy,de                                          ;#6744: FD 19
        ld      hl,(BIOS_GRPCOL)                               ;#6746: 2A C9 F3
        add     hl,de                                          ;#6749: 19
        rrca                                                   ;#674A: 0F
        rrca                                                   ;#674B: 0F
        rrca                                                   ;#674C: 0F
        and     1Fh                                            ;#674D: E6 1F
        ld      c,a                                            ;#674F: 4F
        ld      b,0                                            ;#6750: 06 00
        ld      a,(BIOS_RG7SAV)                                ;#6752: 3A E6 F3
        ld      d,a                                            ;#6755: 57
        and     0Fh                                            ;#6756: E6 0F
        ld      e,a                                            ;#6758: 5F
        pop     af                                             ;#6759: F1
        push    hl                                             ;#675A: E5
        dec     a                                              ;#675B: 3D
        jr      nz,RENDER_CELL_FETCH_ROW                       ;#675C: 20 08
        ld      hl,(BIOS_T32COL)                               ;#675E: 2A BF F3
        add     hl,bc                                          ;#6761: 09
        call    BIOS_RDVRM                                     ;#6762: CD 4A 00
        ld      d,a                                            ;#6765: 57
RENDER_CELL_FETCH_ROW:
        ; Read pattern-table byte + colour byte for one of the 8 rows of the cell
        ld      hl,MEGA_EDITOR_CELL_BUF                        ;#6766: 21 3C FA
        ld      b,8                                            ;#6769: 06 08
RENDER_CELL_FETCH_ROW_LOOP:
        ; Per-row body: read VRAM byte, SCRMOD-branch, process pixel
        push    iy                                             ;#676B: FD E5
        ex      (sp),hl                                        ;#676D: E3
        call    BIOS_RDVRM                                     ;#676E: CD 4A 00
        ld      c,a                                            ;#6771: 4F
        pop     hl                                             ;#6772: E1
        inc     iy                                             ;#6773: FD 23
        ld      a,(BIOS_SCRMOD)                                ;#6775: 3A AF FC
        sub     2                                              ;#6778: D6 02
        jr      c,RENDER_CELL_PROCESS_BYTE                     ;#677A: 38 15
        jr      z,RENDER_CELL_SCR2_PATH                        ;#677C: 28 0C
        ld      d,c                                            ;#677E: 51
        ld      c,0F0h                                         ;#677F: 0E F0
        ld      a,b                                            ;#6781: 78
        cp      5                                              ;#6782: FE 05
        jr      z,RENDER_CELL_PROCESS_BYTE                     ;#6784: 28 0B
        dec     iy                                             ;#6786: FD 2B
        jr      RENDER_CELL_PROCESS_BYTE                       ;#6788: 18 07

RENDER_CELL_SCR2_PATH:
        ; SCRMOD 2 (graphic-2) arm — second VRAM read (colour table) before process
        ex      (sp),hl                                        ;#678A: E3
        call    BIOS_RDVRM                                     ;#678B: CD 4A 00
        ld      d,a                                            ;#678E: 57
        inc     hl                                             ;#678F: 23
        ex      (sp),hl                                        ;#6790: E3
RENDER_CELL_PROCESS_BYTE:
        ; After per-byte VRAM read — convert 1bpp pattern + colour byte into 8 glyph bytes
        push    bc                                             ;#6791: C5
        ld      b,8                                            ;#6792: 06 08
RENDER_CELL_PIXEL_LOOP:
        ; 8-pixel inner body: rotate colour byte, emit glyph bit
        rl      c                                              ;#6794: CB 11
        inc     (hl)                                           ;#6796: 34
        dec     (hl)                                           ;#6797: 35
        jr      nz,RENDER_CELL_PIXEL_ADVANCE                   ;#6798: 20 0D
        ld      a,d                                            ;#679A: 7A
        jr      nc,RENDER_CELL_PIXEL_HI                        ;#679B: 30 04
        rrca                                                   ;#679D: 0F
        rrca                                                   ;#679E: 0F
        rrca                                                   ;#679F: 0F
        rrca                                                   ;#67A0: 0F
RENDER_CELL_PIXEL_HI:
        ; High-nibble colour arm — mask 0Fh, fall to set-pixel
        and     0Fh                                            ;#67A1: E6 0F
        jr      nz,RENDER_CELL_PIXEL_STORE                     ;#67A3: 20 01
        ld      a,e                                            ;#67A5: 7B
RENDER_CELL_PIXEL_STORE:
        ; Common store — write fg/bg colour byte into the glyph buffer
        ld      (hl),a                                         ;#67A6: 77
RENDER_CELL_PIXEL_ADVANCE:
        ; Inner-bit advance — inc HL, djnz back to bit-process body
        inc     hl                                             ;#67A7: 23
        djnz    RENDER_CELL_PIXEL_LOOP                         ;#67A8: 10 EA
        pop     bc                                             ;#67AA: C1
        djnz    RENDER_CELL_FETCH_ROW_LOOP                     ;#67AB: 10 BE
        pop     hl                                             ;#67AD: E1
        pop     iy                                             ;#67AE: FD E1
        pop     hl                                             ;#67B0: E1
        pop     de                                             ;#67B1: D1
        pop     bc                                             ;#67B2: C1
        ret                                                    ;#67B3: C9

SPRITE_CELL_TO_PIXEL:
        ; Convert cell coords B,C to pixel coords (×8+7)
        ld      a,b                                            ;#67B4: 78
        rlca                                                   ;#67B5: 07
        rlca                                                   ;#67B6: 07
        rlca                                                   ;#67B7: 07
        add     a,7                                            ;#67B8: C6 07
        ld      b,a                                            ;#67BA: 47
        ld      a,c                                            ;#67BB: 79
        rlca                                                   ;#67BC: 07
        rlca                                                   ;#67BD: 07
        rlca                                                   ;#67BE: 07
        add     a,7                                            ;#67BF: C6 07
        ld      c,a                                            ;#67C1: 4F
        xor     a                                              ;#67C2: AF
SPRITE_SCAN_LOOP:
        ; Sprite-attribute walk — read sprite at index, accumulate hit list
        call    BIOS_CALATR                                    ;#67C3: CD 87 00
        ld      d,a                                            ;#67C6: 57
        call    BIOS_RDVRM                                     ;#67C7: CD 4A 00
        cp      0D0h                                           ;#67CA: FE D0
        ret     z                                              ;#67CC: C8
        push    de                                             ;#67CD: D5
        push    bc                                             ;#67CE: C5
        call    SPRITE_HIT_TEST                                ;#67CF: CD DA 67
        pop     bc                                             ;#67D2: C1
        pop     af                                             ;#67D3: F1
        inc     a                                              ;#67D4: 3C
        cp      " "                                            ;#67D5: FE 20
        jr      nz,SPRITE_SCAN_LOOP                            ;#67D7: 20 EA
        ret                                                    ;#67D9: C9

SPRITE_HIT_TEST:
        ; Per-sprite hit test: compute delta, bounds-check (<27h)
        sub     c                                              ;#67DA: 91
        cpl                                                    ;#67DB: 2F
        cp      "'"                                            ;#67DC: FE 27
        ret     nc                                             ;#67DE: D0
        ld      c,a                                            ;#67DF: 4F
        inc     hl                                             ;#67E0: 23
        call    BIOS_RDVRM                                     ;#67E1: CD 4A 00
        ld      e,a                                            ;#67E4: 5F
        ld      a,b                                            ;#67E5: 78
        sub     e                                              ;#67E6: 93
        ld      e,a                                            ;#67E7: 5F
        sbc     a,a                                            ;#67E8: 9F
        ld      d,a                                            ;#67E9: 57
        inc     hl                                             ;#67EA: 23
        call    BIOS_RDVRM                                     ;#67EB: CD 4A 00
        ld      b,a                                            ;#67EE: 47
        inc     hl                                             ;#67EF: 23
        call    BIOS_RDVRM                                     ;#67F0: CD 4A 00
        bit     7,a                                            ;#67F3: CB 7F
        jr      z,SPRITE_CELL_FILTER                           ;#67F5: 28 05
        ld      hl,20h                                         ;#67F7: 21 20 00
        add     hl,de                                          ;#67FA: 19
        ex      de,hl                                          ;#67FB: EB
SPRITE_CELL_FILTER:
        ; Sprite attribute analyzed — adjust DE pointer, refine colour by RG1SAV
        inc     d                                              ;#67FC: 14
        dec     d                                              ;#67FD: 15
        ret     nz                                             ;#67FE: C0
        and     0Fh                                            ;#67FF: E6 0F
        ret     z                                              ;#6801: C8
        ld      d,a                                            ;#6802: 57
        ld      a,(BIOS_RG1SAV)                                ;#6803: 3A E0 F3
        bit     1,a                                            ;#6806: CB 4F
        rrca                                                   ;#6808: 0F
        ld      a,8                                            ;#6809: 3E 08
        jr      nc,SPRITE_CELL_NO_DBL                          ;#680B: 30 01
        add     a,a                                            ;#680D: 87
SPRITE_CELL_NO_DBL:
        ; Sprite double-size cleared — A=8, fall to addr-compute
        jr      z,SPRITE_CELL_LOOKUP_BUF                       ;#680E: 28 05
        res     0,b                                            ;#6810: CB 80
        res     1,b                                            ;#6812: CB 88
        add     a,a                                            ;#6814: 87
SPRITE_CELL_LOOKUP_BUF:
        ; Index into sprite-overlap buffer at A — store pixel
        ld      l,a                                            ;#6815: 6F
        add     a,6                                            ;#6816: C6 06
        cp      c                                              ;#6818: B9
        ret     c                                              ;#6819: D8
        cp      e                                              ;#681A: BB
        ret     c                                              ;#681B: D8
        ld      a,c                                            ;#681C: 79
        sub     7                                              ;#681D: D6 07
        ld      c,a                                            ;#681F: 4F
        ld      a,l                                            ;#6820: 7D
        ld      h,8                                            ;#6821: 26 08
        jr      c,SPRITE_CELL_CLAMP_X_DONE                     ;#6823: 38 08
        sub     c                                              ;#6825: 91
        cp      9                                              ;#6826: FE 09
        jr      c,SPRITE_CELL_CLAMP_X                          ;#6828: 38 02
        ld      a,8                                            ;#682A: 3E 08
SPRITE_CELL_CLAMP_X:
        ; X-coord >9 — clamp H to 8
        ld      h,a                                            ;#682C: 67
SPRITE_CELL_CLAMP_X_DONE:
        ; Common arm — load H=A, fall into Y compute
        ld      a,e                                            ;#682D: 7B
        sub     7                                              ;#682E: D6 07
        ld      e,a                                            ;#6830: 5F
        ld      a,l                                            ;#6831: 7D
        ld      l,8                                            ;#6832: 2E 08
        jr      c,RENDER_CELL_SPRITE_OVERLAY                   ;#6834: 38 08
        sub     e                                              ;#6836: 93
        cp      9                                              ;#6837: FE 09
        jr      c,SPRITE_CELL_CLAMP_Y_DONE                     ;#6839: 38 02
        ld      a,8                                            ;#683B: 3E 08
SPRITE_CELL_CLAMP_Y_DONE:
        ; Common arm — load L=A, fall into glyph-overlay
        ld      l,a                                            ;#683D: 6F
RENDER_CELL_SPRITE_OVERLAY:
        ; Compose sprite glyph bits onto the row buffer at MEGA_EDITOR_CELL_BUF
        ld      iy,MEGA_EDITOR_CELL_BUF                        ;#683E: FD 21 3C FA
OVERLAY_X_OUTER_LOOP:
        ; Outer loop over X positions (push DE for restoring)
        push    de                                             ;#6842: D5
        bit     7,c                                            ;#6843: CB 79
        jr      nz,OVERLAY_X_OUT_NEG                           ;#6845: 20 48
        push    hl                                             ;#6847: E5
        push    iy                                             ;#6848: FD E5
OVERLAY_X_NEG_CHECK:
        ; Skip overlay if X<0 (high bit of C set)
        bit     7,e                                            ;#684A: CB 7B
        jr      nz,OVERLAY_BIT_NEXT                            ;#684C: 20 38
        ld      a,(iy)                                         ;#684E: FD 7E 00
        or      a                                              ;#6851: B7
        jr      nz,OVERLAY_BIT_NEXT                            ;#6852: 20 32
        push    bc                                             ;#6854: C5
        push    de                                             ;#6855: D5
        push    hl                                             ;#6856: E5
        ld      a,(BIOS_RG1SAV)                                ;#6857: 3A E0 F3
        rrca                                                   ;#685A: 0F
        jr      nc,OVERLAY_SCRMOD2_DOUBLE                      ;#685B: 30 04
        srl     c                                              ;#685D: CB 39
        srl     e                                              ;#685F: CB 3B
OVERLAY_SCRMOD2_DOUBLE:
        ; SCRMOD-2 wide-pixel arm — shift X and Y right by 1 (doubled pixels)
        bit     3,e                                            ;#6861: CB 5B
        jr      z,OVERLAY_E_BIT3_HI                            ;#6863: 28 04
        res     3,e                                            ;#6865: CB 9B
        set     4,c                                            ;#6867: CB E1
OVERLAY_E_BIT3_HI:
        ; E bit-3 set — clear bit 3, set bit 4 of C (next-cell wraparound)
        ld      l,b                                            ;#6869: 68
        ld      h,0                                            ;#686A: 26 00
        ld      b,h                                            ;#686C: 44
        add     hl,hl                                          ;#686D: 29
        add     hl,hl                                          ;#686E: 29
        add     hl,hl                                          ;#686F: 29
        add     hl,bc                                          ;#6870: 09
        ld      bc,(BIOS_PATBAS)                               ;#6871: ED 4B 26 F9
        add     hl,bc                                          ;#6875: 09
        call    BIOS_RDVRM                                     ;#6876: CD 4A 00
        inc     e                                              ;#6879: 1C
OVERLAY_BIT_ROTATE:
        ; Inner bit-by-bit rotate of sprite byte, search for nonzero pixel
        rlca                                                   ;#687A: 07
        dec     e                                              ;#687B: 1D
        jr      nz,OVERLAY_BIT_ROTATE                          ;#687C: 20 FC
        jr      nc,OVERLAY_BIT_PLACE                           ;#687E: 30 03
        ld      (iy),d                                         ;#6880: FD 72 00
OVERLAY_BIT_PLACE:
        ; Pixel found — overlay it into MEGA_EDITOR_CELL_BUF (set glyph bit)
        pop     hl                                             ;#6883: E1
        pop     de                                             ;#6884: D1
        pop     bc                                             ;#6885: C1
OVERLAY_BIT_NEXT:
        ; Advance to next bit/column — inc iy, inc E, dec L, loop if more
        inc     iy                                             ;#6886: FD 23
        inc     e                                              ;#6888: 1C
        dec     l                                              ;#6889: 2D
        jr      nz,OVERLAY_X_NEG_CHECK                         ;#688A: 20 BE
        pop     iy                                             ;#688C: FD E1
        pop     hl                                             ;#688E: E1
OVERLAY_X_OUT_NEG:
        ; X out of negative range — skip 8 bytes ahead (advance to next column)
        ld      de,8                                           ;#688F: 11 08 00
        add     iy,de                                          ;#6892: FD 19
        pop     de                                             ;#6894: D1
        inc     c                                              ;#6895: 0C
        dec     h                                              ;#6896: 25
        jr      nz,OVERLAY_X_OUTER_LOOP                        ;#6897: 20 A9
        ret                                                    ;#6899: C9

CHECK_GREY_MODE:
        ; Test FFF0h bit 0: Z = colour mode, NZ = grey/monochrome mode
        push    hl                                             ;#689A: E5
        ld      hl,BIOS_RG17SA                                 ;#689B: 21 F0 FF
        bit     0,(hl)                                         ;#689E: CB 46
        pop     hl                                             ;#68A0: E1
        ret                                                    ;#68A1: C9

DUMP_BIT_REORDER_TABLE:
        ; 14-byte bit-pattern lookup indexed by DUMP grey-mode pixel routine (7F12)
        ; Format: FORMAT_BIT_LOOKUP_TABLE
        ; - Each byte is a pre-computed bit pattern selected via `add hl,bc; ld a,(hl)`
        ; - by routines that need a small constant table (printer-pin maps, character
        ; - patterns, mode-translation matrices, etc.). Rendered as raw hex because
        ; - the bytes are data, not encoded instructions.
        dh      "1F1A051D181C03070604021B1901"                 ;#68A2: 1F 1A 05 1D 18 1C 03 07 06 04 02 1B 19 01
        rept    8
        nop
        endr

MEGA_CMD_COPYVR:
        ; `CALL COPYVR` handler — copy main RAM region to VRAM
        pop     hl                                             ;#68B8: E1
        call    PARSE_COPY_ARGS                                ;#68B9: CD 98 7F
        push    hl                                             ;#68BC: E5
        ld      hl,(MEGA_HEADER_TYPE)                          ;#68BD: 2A 30 FA
        ex      de,hl                                          ;#68C0: EB
        ld      hl,(MEGA_SCRATCH_W2)                           ;#68C1: 2A 32 FA
        and     a                                              ;#68C4: A7
        sbc     hl,de                                          ;#68C5: ED 52
        jr      c,COPYVR_BAD_ARG                               ;#68C7: 38 10
        inc     hl                                             ;#68C9: 23
        push    hl                                             ;#68CA: E5
        pop     bc                                             ;#68CB: C1
        ld      hl,(MEGA_HEADER_TYPE)                          ;#68CC: 2A 30 FA
        ld      de,(MEGA_SCRATCH_W3)                           ;#68CF: ED 5B 34 FA
        call    BIOS_LDIRMV                                    ;#68D3: CD 59 00
COPYVR_DONE:
        ; Restore HL after LDIRMV, clear carry, return
        pop     hl                                             ;#68D6: E1
        and     a                                              ;#68D7: A7
        ret                                                    ;#68D8: C9

COPYVR_BAD_ARG:
        ; Raise BASIC error 5 ("Illegal function call") via CALBAS — bad src/dst/len arg
        ld      e,5                                            ;#68D9: 1E 05
        ld      ix,BIOS_BASIC_ERROR_HANDLER                    ;#68DB: DD 21 6F 40
        jp      BIOS_CALBAS                                    ;#68DF: C3 59 01
        rept    9
        nop
        endr

MEGA_CMD_COPYRV:
        ; `CALL COPYRV` handler — copy VRAM region back to main RAM
        pop     hl                                             ;#68EB: E1
        call    PARSE_COPY_ARGS                                ;#68EC: CD 98 7F
        push    hl                                             ;#68EF: E5
        ld      de,(MEGA_HEADER_TYPE)                          ;#68F0: ED 5B 30 FA
        ld      hl,(MEGA_SCRATCH_W2)                           ;#68F4: 2A 32 FA
        and     a                                              ;#68F7: A7
        sbc     hl,de                                          ;#68F8: ED 52
        jr      c,COPYVR_BAD_ARG                               ;#68FA: 38 DD
        inc     hl                                             ;#68FC: 23
        push    hl                                             ;#68FD: E5
        pop     bc                                             ;#68FE: C1
        ld      hl,(MEGA_HEADER_TYPE)                          ;#68FF: 2A 30 FA
        ld      de,(MEGA_SCRATCH_W3)                           ;#6902: ED 5B 34 FA
        call    BIOS_LDIRVM                                    ;#6906: CD 5C 00
        jr      COPYVR_DONE                                    ;#6909: 18 CB

TAPE_ACCESS_ERROR:
        ; TAPOOF then jp PRINT_ACCESS_ERROR — used when cassette read fails mid-stream
        call    BIOS_TAPOOF                                    ;#690B: CD F0 00
        jp      PRINT_ACCESS_ERROR                             ;#690E: C3 8C 7A

CHECK_COPY_PROTECTION:
        ; Try `inc (4000h)`; if ROM mirrored to RAM the byte changes — branch to fail
        xor     a                                              ;#6911: AF
        ld      l,a                                            ;#6912: 6F
        or      20h                                            ;#6913: F6 20
        rlca                                                   ;#6915: 07
        ld      h,a                                            ;#6916: 67
        push    hl                                             ;#6917: E5
        pop     iy                                             ;#6918: FD E1
        ld      c,(iy)                                         ;#691A: FD 4E 00
        inc     (iy)                                           ;#691D: FD 34 00
        ld      a,c                                            ;#6920: 79
        cp      (iy)                                           ;#6921: FD BE 00
        jp      nz,COPY_PROTECTION_FAIL                        ;#6924: C2 12 6C
        in      a,(0A8h)                                       ;#6927: DB A8
        ld      (MEGA_SCRATCH_W2),a                            ;#6929: 32 32 FA
        ret                                                    ;#692C: C9

READ_SLOT_REG_PAGE3:
        ; Read PPI 0A8h; mask the high nibble (page-3 slot bits) into C; ret
        in      a,(0A8h)                                       ;#692D: DB A8
        and     0F0h                                           ;#692F: E6 F0
        ld      c,a                                            ;#6931: 4F
        ret                                                    ;#6932: C9
        rept    9
        nop
        endr

MEGA_INSTALL_DRIVER:
        ; Install the resident slot-aware driver (probe slots, LDIR to C100h, call it)
        ; MEGA_INSTALL_DRIVER — final stage of `MEGA_CMD_START` boot. Runs the
        ; copy-protection check at 6911h (`inc (4000h)` — ROM is read-only so the
        ; byte is unchanged on a legit cart; a RAM-mirrored copy mutates and trips
        ; the JP NZ branch to `COPY_PROTECTION_FAIL` at 6C12h). Then probes
        ; EXPTBL/SLTTBL via PROBE_SLOT_TABLE (6995h), confirms BIOS_BOTTOM is
        ; `8000h` (the cart requires a 32K-RAM system layout), and LDIRs 196 bytes
        ; of RESIDENT_DRIVER_SRC (69F0h) into C100h. Finally `call 0C100h` jumps
        ; into the resident driver. The pattern matches STARTING_GUIDE.md's
        ; "Writes to ROM addresses (copy-protection)" canary description exactly.
        in      a,(0A8h)                                       ;#693C: DB A8
        call    CHECK_COPY_PROTECTION                          ;#693E: CD 11 69
        ld      a,(BIOS_EXPTBL)                                ;#6941: 3A C1 FC
        ld      (MEGA_HEADER_TYPE),a                           ;#6944: 32 30 FA
        ld      (MEGA_SLOT_PATCH),a                            ;#6947: 32 31 FA
        ld      c,0                                            ;#694A: 0E 00
        call    PROBE_SLOT_TABLE                               ;#694C: CD 95 69
        jr      c,MEGA_INSTALL_PAGE_HIGH                       ;#694F: 38 03
        ld      (MEGA_HEADER_TYPE),a                           ;#6951: 32 30 FA
MEGA_INSTALL_PAGE_HIGH:
        ; Probe upper slot half (C=40h) for cartridges, save into FA31h
        ld      c,40h                                          ;#6954: 0E 40
        call    PROBE_SLOT_TABLE                               ;#6956: CD 95 69
        jr      c,MEGA_INSTALL_CHECK_SLOT                      ;#6959: 38 03
        ld      (MEGA_SLOT_PATCH),a                            ;#695B: 32 31 FA
MEGA_INSTALL_CHECK_SLOT:
        ; Walk BIOS_SLTTBL+4 looking for unset entries — fail if any are negative
        ld      hl,BIOS_SLTTBL+4                               ;#695E: 21 C9 FC
        ld      b,40h                                          ;#6961: 06 40
MEGA_INSTALL_SLTTBL_LOOP:
        ; Per-byte body — test sign bit of SLTTBL entry; fail on negative
        ld      a,(hl)                                         ;#6963: 7E
        add     a,a                                            ;#6964: 87
        jr      c,MEGA_INSTALL_DRIVER_FAIL                     ;#6965: 38 2B
        inc     hl                                             ;#6967: 23
        djnz    MEGA_INSTALL_SLTTBL_LOOP                       ;#6968: 10 F9
        ld      hl,(BIOS_BOTTOM)                               ;#696A: 2A 48 FC
        ld      de,8000h                                       ;#696D: 11 00 80
        or      a                                              ;#6970: B7
        sbc     hl,de                                          ;#6971: ED 52
        jr      nz,MEGA_INSTALL_DRIVER_FAIL                    ;#6973: 20 1D
        ld      hl,MEGA_HEADER_TYPE                            ;#6975: 21 30 FA
        ld      a,(BIOS_EXPTBL)                                ;#6978: 3A C1 FC
        cp      (hl)                                           ;#697B: BE
        jr      z,MEGA_INSTALL_DRIVER_FAIL                     ;#697C: 28 14
        inc     hl                                             ;#697E: 23
        cp      (hl)                                           ;#697F: BE
        jr      z,MEGA_INSTALL_DRIVER_FAIL                     ;#6980: 28 10
        ld      hl,RESIDENT_DRIVER_SRC                         ;#6982: 21 F0 69
        ld      de,DRIVER_INIT_SLOTS                           ;#6985: 11 00 C1
        ld      bc,MEGA_TOP_BANNER-RESIDENT_DRIVER_SRC         ;#6988: 01 C4 00
        ldir                                                   ;#698B: ED B0
        call    DRIVER_INIT_SLOTS                              ;#698D: CD 00 C1
        or      a                                              ;#6990: B7
        ret                                                    ;#6991: C9

MEGA_INSTALL_DRIVER_FAIL:
        ; Failure tail: `ei` then `scf; ret` (any of 4 sanity checks failed)
        ei                                                     ;#6992: FB
        scf                                                    ;#6993: 37
        ret                                                    ;#6994: C9

PROBE_SLOT_TABLE:
        ; Walk EXPTBL/SLTTBL looking for cartridges in the slot range selected by C
        ld      hl,BIOS_EXPTBL                                 ;#6995: 21 C1 FC
        ld      b,4                                            ;#6998: 06 04
        xor     a                                              ;#699A: AF
PROBE_NEXT_SLOT_BIT:
        ; Per-slot probe head: mask & merge EXPTBL slot bits
        and     3                                              ;#699B: E6 03
        or      (hl)                                           ;#699D: B6
PROBE_NEXT_SUBSLOT:
        ; Per-subslot body — push regs, set L=10h test value, probe via RDSLT/WRSLT
        push    bc                                             ;#699E: C5
        push    hl                                             ;#699F: E5
        ld      h,c                                            ;#69A0: 61
PROBE_SUBSLOT_PROBE:
        ; Set L=10h, push, call BIOS_RDSLT, complement, write, verify, restore
        ld      l,10h                                          ;#69A1: 2E 10
PROBE_SUBSLOT_RDWR:
        ; Inner read/write/compare body — verifies a slot really has RAM
        push    af                                             ;#69A3: F5
        call    BIOS_RDSLT                                     ;#69A4: CD 0C 00
        cpl                                                    ;#69A7: 2F
        ld      e,a                                            ;#69A8: 5F
        pop     af                                             ;#69A9: F1
        push    de                                             ;#69AA: D5
        push    af                                             ;#69AB: F5
        call    BIOS_WRSLT                                     ;#69AC: CD 14 00
        pop     af                                             ;#69AF: F1
        pop     de                                             ;#69B0: D1
        push    af                                             ;#69B1: F5
        push    de                                             ;#69B2: D5
        call    BIOS_RDSLT                                     ;#69B3: CD 0C 00
        pop     bc                                             ;#69B6: C1
        ld      b,a                                            ;#69B7: 47
        ld      a,c                                            ;#69B8: 79
        cpl                                                    ;#69B9: 2F
        ld      e,a                                            ;#69BA: 5F
        pop     af                                             ;#69BB: F1
        push    af                                             ;#69BC: F5
        push    bc                                             ;#69BD: C5
        call    BIOS_WRSLT                                     ;#69BE: CD 14 00
        pop     bc                                             ;#69C1: C1
        ld      a,c                                            ;#69C2: 79
        cp      b                                              ;#69C3: B8
        jr      nz,PROBE_SUBSLOT_FAIL                          ;#69C4: 20 17
        pop     af                                             ;#69C6: F1
        dec     l                                              ;#69C7: 2D
        jr      nz,PROBE_SUBSLOT_RDWR                          ;#69C8: 20 D9
        inc     h                                              ;#69CA: 24
        inc     h                                              ;#69CB: 24
        inc     h                                              ;#69CC: 24
        inc     h                                              ;#69CD: 24
        ld      c,a                                            ;#69CE: 4F
        ld      a,h                                            ;#69CF: 7C
        cp      40h                                            ;#69D0: FE 40
        jr      z,PROBE_SUBSLOT_MATCH                          ;#69D2: 28 05
        cp      80h                                            ;#69D4: FE 80
        ld      a,c                                            ;#69D6: 79
        jr      nz,PROBE_SUBSLOT_PROBE                         ;#69D7: 20 C8
PROBE_SUBSLOT_MATCH:
        ; Slot probe matched (H=40h) — A=C and pop, ret with cart slot in A
        ld      a,c                                            ;#69D9: 79
        pop     hl                                             ;#69DA: E1
        pop     hl                                             ;#69DB: E1
        ret                                                    ;#69DC: C9

PROBE_SUBSLOT_FAIL:
        ; Probe missed — pop AF/HL/BC, advance to next subslot
        pop     af                                             ;#69DD: F1
        pop     hl                                             ;#69DE: E1
        pop     bc                                             ;#69DF: C1
        or      a                                              ;#69E0: B7
        jp      p,PROBE_SUBSLOT_ADVANCE                        ;#69E1: F2 EA 69
        add     a,4                                            ;#69E4: C6 04
        cp      90h                                            ;#69E6: FE 90
        jr      c,PROBE_NEXT_SUBSLOT                           ;#69E8: 38 B4
PROBE_SUBSLOT_ADVANCE:
        ; Next slot — inc HL, inc A, djnz back to per-subslot body
        inc     hl                                             ;#69EA: 23
        inc     a                                              ;#69EB: 3C
        djnz    PROBE_NEXT_SLOT_BIT                            ;#69EC: 10 AD
        scf                                                    ;#69EE: 37
        ret                                                    ;#69EF: C9

RESIDENT_DRIVER_SRC:
        ; ROM source of the 196-byte resident driver (LDIRed to C100h)

        phase   0C100h
DRIVER_INIT_SLOTS:
        ; Resident-driver entry — programmes page 0/1 subslots from saved FA30/FA31/FA32
        ld      a,(MEGA_HEADER_TYPE)                           ;#C100: 3A 30 FA
        ld      h,0                                            ;#C103: 26 00
        call    SET_PAGE_SUBSLOT                               ;#C105: CD 1C C1
        ld      a,(MEGA_SLOT_PATCH)                            ;#C108: 3A 31 FA
        ld      h,40h                                          ;#C10B: 26 40
        call    SET_PAGE_SUBSLOT                               ;#C10D: CD 1C C1
        in      a,(0A8h)                                       ;#C110: DB A8
        push    af                                             ;#C112: F5
        ld      a,(MEGA_SCRATCH_W2)                            ;#C113: 3A 32 FA
        out     (0A8h),a                                       ;#C116: D3 A8
        ld      b,a                                            ;#C118: 47
        pop     af                                             ;#C119: F1
        ei                                                     ;#C11A: FB
        ret                                                    ;#C11B: C9

SET_PAGE_SUBSLOT:
        ; Given page index in H and subslot in A, write the bits via either A8 or FFFFh
        call    DECODE_PAGE_SLOT                               ;#C11C: CD 49 C1
        jp      m,SET_PAGE_SUBSLOT_EXPANDED                    ;#C11F: FA 29 C1
        in      a,(0A8h)                                       ;#C122: DB A8
        and     c                                              ;#C124: A1
        or      b                                              ;#C125: B0
        out     (0A8h),a                                       ;#C126: D3 A8
        ret                                                    ;#C128: C9

SET_PAGE_SUBSLOT_EXPANDED:
        ; Expanded-slot path — write subslot to FFFFh via UPDATE_SUBSLOT_REG
        call    PAGE_SLOT_VALID_CHECK                          ;#C129: CD 98 C1
        jr      z,SET_PAGE_SUBSLOT_FALLBACK                    ;#C12C: 28 13
        push    hl                                             ;#C12E: E5
        call    READ_SUBSLOT_FOR_PAGE                          ;#C12F: CD 6E C1
        ld      c,a                                            ;#C132: 4F
        ld      b,0                                            ;#C133: 06 00
        ld      a,l                                            ;#C135: 7D
        and     h                                              ;#C136: A4
        or      d                                              ;#C137: B2
        ld      hl,BIOS_SLTTBL                                 ;#C138: 21 C5 FC
        add     hl,bc                                          ;#C13B: 09
        ld      (hl),a                                         ;#C13C: 77
        pop     hl                                             ;#C13D: E1
        ld      a,c                                            ;#C13E: 79
        jr      SET_PAGE_SUBSLOT                               ;#C13F: 18 DB

SET_PAGE_SUBSLOT_FALLBACK:
        ; Fallback path when PAGE_SLOT_VALID_CHECK reports the page isn't expanded
        call    UPDATE_SUBSLOT_REG                             ;#C141: CD A1 C1
        ld      hl,BIOS_SLTTBL                                 ;#C144: 21 C5 FC
        ld      (hl),d                                         ;#C147: 72
        ret                                                    ;#C148: C9

DECODE_PAGE_SLOT:
        ; Compute primary-slot mask for the page H selects; M = not expanded
        di                                                     ;#C149: F3
        push    af                                             ;#C14A: F5
        ld      a,h                                            ;#C14B: 7C
        rlca                                                   ;#C14C: 07
        rlca                                                   ;#C14D: 07
        and     3                                              ;#C14E: E6 03
        ld      e,a                                            ;#C150: 5F
        inc     e                                              ;#C151: 1C
        ld      a,0C0h                                         ;#C152: 3E C0
SUBSLOT_MASK_SHIFT:
        ; Shift mask C0h left by (e+1) ticks to select target subslot bits
        rlca                                                   ;#C154: 07
        rlca                                                   ;#C155: 07
        dec     e                                              ;#C156: 1D
        jr      nz,SUBSLOT_MASK_SHIFT                          ;#C157: 20 FB
        ld      e,a                                            ;#C159: 5F
        cpl                                                    ;#C15A: 2F
        ld      c,a                                            ;#C15B: 4F
        pop     af                                             ;#C15C: F1
        push    af                                             ;#C15D: F5
        and     3                                              ;#C15E: E6 03
        ld      b,a                                            ;#C160: 47
        inc     b                                              ;#C161: 04
        ld      a,0ABh                                         ;#C162: 3E AB
SUBSLOT_WRITE_ROTATE:
        ; Inner rotate — multiply ABh by (b+1) to position the write mask into place
        add     a,55h                                          ;#C164: C6 55
        djnz    SUBSLOT_WRITE_ROTATE                           ;#C166: 10 FC
        ld      d,a                                            ;#C168: 57
        and     e                                              ;#C169: A3
        ld      b,a                                            ;#C16A: 47
        pop     af                                             ;#C16B: F1
        or      a                                              ;#C16C: B7
        ret                                                    ;#C16D: C9

READ_SUBSLOT_FOR_PAGE:
        ; Read the current subslot bits for the page H selects via FFFFh
        push    af                                             ;#C16E: F5
        ld      a,d                                            ;#C16F: 7A
        and     0C0h                                           ;#C170: E6 C0
        ld      c,a                                            ;#C172: 4F
        pop     af                                             ;#C173: F1
        push    af                                             ;#C174: F5
        ld      d,a                                            ;#C175: 57
        in      a,(0A8h)                                       ;#C176: DB A8
        ld      b,a                                            ;#C178: 47
        and     3Fh                                            ;#C179: E6 3F
        or      c                                              ;#C17B: B1
        push    af                                             ;#C17C: F5
        ld      a,d                                            ;#C17D: 7A
        rrca                                                   ;#C17E: 0F
        rrca                                                   ;#C17F: 0F
        and     3                                              ;#C180: E6 03
        ld      d,a                                            ;#C182: 57
        inc     d                                              ;#C183: 14
        ld      a,0ABh                                         ;#C184: 3E AB
SUBSLOT_READ_ROTATE:
        ; Inner rotate — multiply 55h by d to position the read mask into place
        add     a,55h                                          ;#C186: C6 55
        dec     d                                              ;#C188: 15
        jr      nz,SUBSLOT_READ_ROTATE                         ;#C189: 20 FB
        and     e                                              ;#C18B: A3
        ld      d,a                                            ;#C18C: 57
        ld      a,e                                            ;#C18D: 7B
        cpl                                                    ;#C18E: 2F
        ld      h,a                                            ;#C18F: 67
        pop     af                                             ;#C190: F1
        call    WRITE_PRIMARY_AND_SUB                          ;#C191: CD B4 C1
        pop     af                                             ;#C194: F1
        and     3                                              ;#C195: E6 03
        ret                                                    ;#C197: C9

PAGE_SLOT_VALID_CHECK:
        ; `inc d / dec d / ret nz` — tests D before main path
        inc     d                                              ;#C198: 14
        dec     d                                              ;#C199: 15
        ret     nz                                             ;#C19A: C0
        ld      b,a                                            ;#C19B: 47
        ld      a,e                                            ;#C19C: 7B
        cp      3                                              ;#C19D: FE 03
        ld      a,b                                            ;#C19F: 78
        ret                                                    ;#C1A0: C9

UPDATE_SUBSLOT_REG:
        ; Read FFFFh (secondary-slot select), OR with masked D, write back
        rrca                                                   ;#C1A1: 0F
        rrca                                                   ;#C1A2: 0F
        and     3                                              ;#C1A3: E6 03
        ld      d,a                                            ;#C1A5: 57
        ld      a,(BIOS_SUBSLOT_REG)                           ;#C1A6: 3A FF FF
        cpl                                                    ;#C1A9: 2F
        ld      b,a                                            ;#C1AA: 47
        and     0FCh                                           ;#C1AB: E6 FC
        or      d                                              ;#C1AD: B2
        ld      d,a                                            ;#C1AE: 57
        ld      (BIOS_SUBSLOT_REG),a                           ;#C1AF: 32 FF FF
        ld      a,e                                            ;#C1B2: 7B
        ret                                                    ;#C1B3: C9

WRITE_PRIMARY_AND_SUB:
        ; Atomic write: A→A8, masked combination→FFFFh, restore A8 from B
        out     (0A8h),a                                       ;#C1B4: D3 A8
        ld      a,(BIOS_SUBSLOT_REG)                           ;#C1B6: 3A FF FF
        cpl                                                    ;#C1B9: 2F
        ld      l,a                                            ;#C1BA: 6F
        and     h                                              ;#C1BB: A4
        or      d                                              ;#C1BC: B2
        ld      (BIOS_SUBSLOT_REG),a                           ;#C1BD: 32 FF FF
        ld      a,b                                            ;#C1C0: 78
        out     (0A8h),a                                       ;#C1C1: D3 A8
        ret                                                    ;#C1C3: C9
        dephase

MEGA_TOP_BANNER:
        ; 76-byte fixed-width banner "\r<<  Mega Assembler 1.0 >>" + 41 spaces + "Pagina "
        db      0Dh, "<<  Mega Assembler 1.0 >>"               ;#6AB4: 0D 3C 3C 20 20 4D 65 ...
        db      "                                          "   ;#6ACE: 20 20 20 20 20 20 20 ...
        db      "Pagina ", 0                                   ;#6AF8: 50 61 67 69 6E 61 20 ...

PRINT_BANNER:
        ; Print the splash banner inline string ("** Mega Assembler 1.0 **\r" + copyright)
        call    PRINT_INLINE_STRING                            ;#6B00: CD 8A 50
        db      0Ch, "** Mega Assembler 1.0 **", 0Dh           ;#6B03: 0C 2A 2A 20 4D 65 67 ...
        db      "Cibertron Software  1987", 0Dh, 8Ah           ;#6B1D: 43 69 62 65 72 74 72 ...
        ret                                                    ;#6B37: C9

MEGA_PCMD_F_BODY:
        ; Body of `F` (find/replace) prompt — store search pattern from HL into EC1A, ret
        ld      a,(hl)                                         ;#6B38: 7E
        or      a                                              ;#6B39: B7
        jp      z,SYNTAX_ERROR                                 ;#6B3A: CA B9 41
        call    SEARCH_PARSE_PATTERN                           ;#6B3D: CD 92 4C
        inc     hl                                             ;#6B40: 23
        ld      (MEGA_SEARCH_PATTERN),hl                       ;#6B41: 22 1A EC
        ret                                                    ;#6B44: C9

MEGA_PCMD_TABLE:
        ; Assembler-prompt command table walked by MEGA_PROMPT_TICK
        ; MEGA_PCMD_TABLE — same record format as BASIC_CMD_TABLE (name with bit 7
        ; set on the last char + 2-byte handler), terminated by a 00 byte. These are
        ; the 35 commands the assembler itself accepts at the `>` prompt — a
        ; full-screen line editor (`NEW`, `LIST`, `LLIST`, `AUTO`, `RENUM`,
        ; `DELETE`, `SEARCH`, `LSEARCH`, `FIND`, `CHANGE`, `MERGE`), file
        ; operations (`SAVE`, `LOAD`, `FILES`, `INTEL`), single-letter
        ; machine-code monitor commands (`A` assemble, `D` display,
        ; `R` register dump, `G` go, `M` move, `S` set/search, `C` compare,
        ; `V` verify, `F` fill, `T` trace, `X` examine, `P` poke, `L` load,
        ; `LP` line-printer toggle), and assembler-specific helpers
        ; (`BA`, `DM` display memory, `MS`, `SH`, `PAGE`, `SCR`, `ZAP`,
        ; `MAP`). The dispatcher at 418C (inside MEGA_PROMPT_TICK) walks this
        ; table the same way BASIC_STATEMENT walks BASIC_CMD_TABLE.
        MEGA_CMD "NEW"C, MEGA_PCMD_NEW                         ;#6B45: 4E 45 D7 41 49
        MEGA_CMD "LIST"C, MEGA_PCMD_LIST                       ;#6B4A: 4C 49 53 D4 8D 49
        MEGA_CMD "LLIST"C, MEGA_PCMD_LLIST                     ;#6B50: 4C 4C 49 53 D4 89 49
        MEGA_CMD "AUTO"C, MEGA_PCMD_AUTO                       ;#6B57: 41 55 54 CF 1A 4E
        MEGA_CMD "RENUM"C, MEGA_PCMD_RENUM                     ;#6B5D: 52 45 4E 55 CD AD 4D
        MEGA_CMD "DELETE"C, MEGA_PCMD_DELETE                   ;#6B64: 44 45 4C 45 54 C5 74 ...
        MEGA_CMD "SEARCH"C, MEGA_PCMD_SEARCH                   ;#6B6C: 53 45 41 52 43 C8 17 ...
        MEGA_CMD "LSEARCH"C, MEGA_PCMD_LSEARCH                 ;#6B74: 4C 53 45 41 52 43 C8 ...
        MEGA_CMD "FIND"C, MEGA_PCMD_FIND                       ;#6B7D: 46 49 4E C4 50 4C
        MEGA_CMD "CHANGE"C, MEGA_PCMD_CHANGE                   ;#6B83: 43 48 41 4E 47 C5 B0 ...
        MEGA_CMD "SAVE"C, MEGA_PCMD_SAVE                       ;#6B8B: 53 41 56 C5 F3 7A
        MEGA_CMD "LOAD"C, MEGA_PCMD_LOAD                       ;#6B91: 4C 4F 41 C4 1D 7A
        MEGA_CMD "MERGE"C, MEGA_PCMD_MERGE                     ;#6B97: 4D 45 52 47 C5 AC 4A
        MEGA_CMD "INTEL"C, MEGA_PCMD_INTEL                     ;#6B9E: 49 4E 54 45 CC 5A 43
        MEGA_CMD "FILES"C, MEGA_PCMD_FILES                     ;#6BA5: 46 49 4C 45 D3 22 7E
        MEGA_CMD "BA"C, MEGA_PCMD_BA                           ;#6BAC: 42 C1 17 49
        MEGA_CMD "DM"C, MEGA_PCMD_DM                           ;#6BB0: 44 CD 8E 73
        MEGA_CMD "MS"C, MEGA_PCMD_MS                           ;#6BB4: 4D D3 FA 77
        MEGA_CMD "SH"C, MEGA_PCMD_SH                           ;#6BB8: 53 C8 EE 76
        MEGA_CMD "PAGE"C, MEGA_PCMD_PAGE                       ;#6BBC: 50 41 47 C5 C0 6C
        MEGA_CMD "SCR"C, MEGA_PCMD_SCR                         ;#6BC2: 53 43 D2 53 6D
        MEGA_CMD "ZAP"C, MEGA_PCMD_ZAP                         ;#6BC7: 5A 41 D0 94 73
        MEGA_CMD "MAP"C, MEGA_PCMD_MAP                         ;#6BCC: 4D 41 D0 2B 49
        MEGA_CMD "A"C, MEGA_PCMD_A                             ;#6BD1: C1 02 51
        MEGA_CMD "R"C, MEGA_PCMD_R                             ;#6BD4: D2 5E 43
        MEGA_CMD "G"C, MEGA_PCMD_G                             ;#6BD7: C7 11 46
        MEGA_CMD "X"C, MEGA_PCMD_X                             ;#6BDA: D8 2B 44
        MEGA_CMD "P"C, MEGA_PCMD_P                             ;#6BDD: D0 CD 47
        MEGA_CMD "D"C, MEGA_PCMD_D                             ;#6BE0: C4 D1 47
        MEGA_CMD "F"C, MEGA_PCMD_F                             ;#6BE3: C6 BF 48
        MEGA_CMD "T"C, MEGA_PCMD_T                             ;#6BE6: D4 FC 48
        MEGA_CMD "M"C, MEGA_PCMD_M                             ;#6BE9: CD 59 47
        MEGA_CMD "S"C, MEGA_PCMD_S                             ;#6BEC: D3 55 47
        MEGA_CMD "V"C, MEGA_PCMD_V                             ;#6BEF: D6 C7 47
        MEGA_CMD "C"C, MEGA_PCMD_C                             ;#6BF2: C3 B0 47
        MEGA_CMD "LP"C, MEGA_PCMD_LP                           ;#6BF5: 4C D0 42 61
        MEGA_CMD "L"C, MEGA_PCMD_L                             ;#6BF9: CC 46 61
        db      0                                              ;#6BFC: 00

SCR_MODE_TO_FLAGS:
        ; Convert SCR's 0/1 mode-arg to MEGA_EDITOR_MODE_FLAGS byte (01h or 41h)
        cp      1                                              ;#6BFD: FE 01
        ld      a,41h                                          ;#6BFF: 3E 41
        ret     z                                              ;#6C01: C8
        ld      a,1                                            ;#6C02: 3E 01
        ret                                                    ;#6C04: C9

EDITOR_WRTVRM_INVERT:
        ; WRTVRM wrapper: complement A first if MEGA_EDITOR_INVERT bit 0 is set
        push    hl                                             ;#6C05: E5
        ld      hl,MEGA_EDITOR_INVERT                          ;#6C06: 21 74 FA
        bit     0,(hl)                                         ;#6C09: CB 46
        pop     hl                                             ;#6C0B: E1
        jr      z,EDITOR_WRTVRM_FALL                           ;#6C0C: 28 01
        cpl                                                    ;#6C0E: 2F
EDITOR_WRTVRM_FALL:
        ; Common tail — jp BIOS_WRTVRM after optional CPL
        jp      BIOS_WRTVRM                                    ;#6C0F: C3 4D 00

COPY_PROTECTION_FAIL:
        ; Reached when CHECK_COPY_PROTECTION detects a RAM-mirrored cart
        ; COPY_PROTECTION_FAIL — anti-piracy wipe. CHECK_COPY_PROTECTION
        ; at 6911 increments byte (4000h) and checks for a change; a real ROM
        ; won't change (write-only-on-real-hardware) but a RAM-cloned cart
        ; will. On detect, this routine does the maximally hostile thing: it
        ; writes the two-byte LDIR opcode (ED B0) to C000h, then jumps to
        ; C000h. The LDIR runs with HL=(saved), DE=HL+1, BC=0, which loops
        ; 65,536 times — copying byte (HL) to (HL+1)..(HL+65535), wiping
        ; the entire address space (including the running LDIR at C000h
        ; itself). Effectively a hard freeze. There is no recovery; the
        ; user can only reset the machine.
        push    hl                                             ;#6C12: E5
        pop     de                                             ;#6C13: D1
        inc     de                                             ;#6C14: 13
        xor     a                                              ;#6C15: AF
        ld      b,a                                            ;#6C16: 47
        ld      c,a                                            ;#6C17: 4F
        ld      (hl),a                                         ;#6C18: 77
        ld      a,Z80_ED_PREFIX                                ;#6C19: 3E ED
        ld      (PAGE_3_RAM),a                                 ;#6C1B: 32 00 C0
        ld      a,Z80_LDIR                                     ;#6C1E: 3E B0
        ld      (PAGE_3_RAM+1),a                               ;#6C20: 32 01 C0
        jp      PAGE_3_RAM                                     ;#6C23: C3 00 C0

PARSE_EDITOR_DATA_BASE:
        ; Default DE=C000h; check terminator (NUL/':' → ret z, else ret nz)
        ld      de,PAGE_3_RAM                                  ;#6C26: 11 00 C0
        and     a                                              ;#6C29: A7
        ret     z                                              ;#6C2A: C8
        cp      ":"                                            ;#6C2B: FE 3A
        ret                                                    ;#6C2D: C9
        nop                                                    ;#6C2E: 00
        nop                                                    ;#6C2F: 00

BASIC_STATEMENT:
        ; STATEMENT handler — dispatch from BASIC `CALL <name>` against BASIC_CMD_TABLE
        ; BASIC STATEMENT-hook dispatch. Walks BASIC_CMD_TABLE comparing each
        ; name (last char carries bit 7 as terminator) against the BASIC name buffer
        ; PROCNM at FD89h. On match, reads the 2-byte LE handler address and
        ; `jp (hl)` to it. On end-of-table (00 byte) returns with carry set so BASIC
        ; raises a "Syntax error" — the documented MSX STATEMENT-hook convention.
        ld      de,BASIC_CMD_TABLE                             ;#6C30: 11 59 6C
        push    hl                                             ;#6C33: E5
BASIC_STATEMENT_LOAD_PROCNM:
        ; Point HL at PROCNM buffer for table walk
        ld      hl,BIOS_PROCNM                                 ;#6C34: 21 89 FD
BASIC_STATEMENT_CMP_BYTE:
        ; Per-char compare of PROCNM vs table name; loop until bit-7 terminator
        ld      a,(de)                                         ;#6C37: 1A
        and     7Fh                                            ;#6C38: E6 7F
        jr      z,BASIC_STATEMENT_NOMATCH                      ;#6C3A: 28 1A
        cp      (hl)                                           ;#6C3C: BE
        jr      nz,BASIC_STATEMENT_SKIP                        ;#6C3D: 20 0D
        ld      a,(de)                                         ;#6C3F: 1A
        inc     hl                                             ;#6C40: 23
        inc     de                                             ;#6C41: 13
        and     80h                                            ;#6C42: E6 80
        jr      z,BASIC_STATEMENT_CMP_BYTE                     ;#6C44: 28 F1
        ex      de,hl                                          ;#6C46: EB
        ld      e,(hl)                                         ;#6C47: 5E
        inc     hl                                             ;#6C48: 23
        ld      d,(hl)                                         ;#6C49: 56
        ex      de,hl                                          ;#6C4A: EB
        jp      (hl)                                           ;#6C4B: E9

BASIC_STATEMENT_SKIP:
        ; No match: skip rest of name (to bit-7 terminator), skip handler addr, retry
        ld      a,(de)                                         ;#6C4C: 1A
        inc     de                                             ;#6C4D: 13
        and     80h                                            ;#6C4E: E6 80
        jr      z,BASIC_STATEMENT_SKIP                         ;#6C50: 28 FA
        inc     de                                             ;#6C52: 13
        inc     de                                             ;#6C53: 13
        jr      BASIC_STATEMENT_LOAD_PROCNM                    ;#6C54: 18 DE

BASIC_STATEMENT_NOMATCH:
        ; End of BASIC_CMD_TABLE — pop saved HL, scf, ret so BASIC raises "Syntax error"
        pop     hl                                             ;#6C56: E1
        scf                                                    ;#6C57: 37
        ret                                                    ;#6C58: C9

BASIC_CMD_TABLE:
        ; Name→handler table walked by BASIC_STATEMENT; 0 terminator
        ; BASIC_CMD_TABLE. Each record is `name_string` (last char ORed with 80h
        ; as terminator) followed by 2-byte LE handler pointer. The whole table is
        ; closed by a 00 byte. Decoded entries (this build):
        ; ASM     -> MEGA_CMD_ASM      (4013)
        ; START   -> MEGA_CMD_START    (4017)
        ; BVERIFY -> MEGA_CMD_BVERIFY  (78A2)
        ; RENEW   -> MEGA_CMD_RENEW    (784E)
        ; EDITOR  -> MEGA_CMD_EDITOR   (71C7)
        ; HEADER  -> MEGA_CMD_HEADER   (792C)
        ; SETGREY -> MEGA_CMD_SETGREY  (7E3B)
        ; SETKEY  -> MEGA_CMD_SETKEY   (7E50)
        ; DUMP    -> MEGA_CMD_DUMP     (7E89)
        ; COPYVR  -> MEGA_CMD_COPYVR   (68B8)
        ; COPYRV  -> MEGA_CMD_COPYRV   (68EB)
        BASIC_CMD "ASM"C, MEGA_CMD_ASM                         ;#6C59: 41 53 CD 13 40
        BASIC_CMD "START"C, MEGA_CMD_START                     ;#6C5E: 53 54 41 52 D4 17 40
        BASIC_CMD "BVERIFY"C, MEGA_CMD_BVERIFY                 ;#6C65: 42 56 45 52 49 46 D9 ...
        BASIC_CMD "RENEW"C, MEGA_CMD_RENEW                     ;#6C6E: 52 45 4E 45 D7 4E 78
        BASIC_CMD "EDITOR"C, MEGA_CMD_EDITOR                   ;#6C75: 45 44 49 54 4F D2 C7 ...
        BASIC_CMD "HEADER"C, MEGA_CMD_HEADER                   ;#6C7D: 48 45 41 44 45 D2 2C ...
        BASIC_CMD "SETGREY"C, MEGA_CMD_SETGREY                 ;#6C85: 53 45 54 47 52 45 D9 ...
        BASIC_CMD "SETKEY"C, MEGA_CMD_SETKEY                   ;#6C8E: 53 45 54 4B 45 D9 50 ...
        BASIC_CMD "DUMP"C, MEGA_CMD_DUMP                       ;#6C96: 44 55 4D D0 89 7E
        BASIC_CMD "COPYVR"C, MEGA_CMD_COPYVR                   ;#6C9C: 43 4F 50 59 56 D2 B8 ...
        BASIC_CMD "COPYRV"C, MEGA_CMD_COPYRV                   ;#6CA4: 43 4F 50 59 52 D6 EB ...
        db      0                                              ;#6CAC: 00

PARSE_REQUIRED_HEX_WORD:
        ; SKIP_SPACES, raise on EOL, set E=0 then PARSE_HEX_WORD — required-arg variant
        call    SKIP_SPACES                                    ;#6CAD: CD F3 43
        jp      z,SYNTAX_ERROR_LF                              ;#6CB0: CA 47 43
        ld      e,0                                            ;#6CB3: 1E 00
        jp      PARSE_HEX_WORD                                 ;#6CB5: C3 BA 50
        rept    8
        nop
        endr

MEGA_PCMD_PAGE:
        ; Prompt command "PAGE" — display page-to-slot mapping
        call    SKIP_SPACES                                    ;#6CC0: CD F3 43
        jr      nz,PAGE_PRINT_REPORT                           ;#6CC3: 20 0E
        call    READ_SLOT_REG_PAGE3                            ;#6CC5: CD 2D 69
        rlca                                                   ;#6CC8: 07
        rlca                                                   ;#6CC9: 07
        rlca                                                   ;#6CCA: 07
        rlca                                                   ;#6CCB: 07
        and     0Fh                                            ;#6CCC: E6 0F
        or      c                                              ;#6CCE: B1
        ld      (MEGA_HOOK_SLOT_PATCH),a                       ;#6CCF: 32 03 FA
        ret                                                    ;#6CD2: C9

PAGE_PRINT_REPORT:
        ; "?" argument path: print "Pagina N = Slot M" for each of the 4 pages
        cp      "?"                                            ;#6CD3: FE 3F
        jr      nz,MEGA_PCMD_PAGE_PARSE_SET                    ;#6CD5: 20 33
        ld      a,(MEGA_HOOK_SLOT_PATCH)                       ;#6CD7: 3A 03 FA
        ld      b,4                                            ;#6CDA: 06 04
        ld      c,a                                            ;#6CDC: 4F
PAGE_PRINT_LOOP:
        ; Per-iteration body — prints one Pagina/Slot row
        call    PRINT_INLINE_STRING                            ;#6CDD: CD 8A 50
        db      "Pagina "C                                     ;#6CE0: 50 61 67 69 6E 61 A0
        ld      a,34h                                          ;#6CE7: 3E 34
        sub     b                                              ;#6CE9: 90
        rst     18h                                            ;#6CEA: DF
        ld      a," "                                          ;#6CEB: 3E 20
        rst     18h                                            ;#6CED: DF
        ld      a,"="                                          ;#6CEE: 3E 3D
        rst     18h                                            ;#6CF0: DF
        call    PRINT_INLINE_STRING                            ;#6CF1: CD 8A 50
        db      " Slot "C                                      ;#6CF4: 20 53 6C 6F 74 A0
        ld      a,c                                            ;#6CFA: 79
        and     3                                              ;#6CFB: E6 03
        add     a,"0"                                          ;#6CFD: C6 30
        rst     18h                                            ;#6CFF: DF
        call    PRINT_CR                                       ;#6D00: CD B4 42
        rrc     c                                              ;#6D03: CB 09
        rrc     c                                              ;#6D05: CB 09
        djnz    PAGE_PRINT_LOOP                                ;#6D07: 10 D4
        ret                                                    ;#6D09: C9

MEGA_PCMD_PAGE_PARSE_SET:
        ; Non-? form: parse up to 4 decimal slot digits, pack into MEGA_HOOK_SLOT_PATCH
        ld      a,(MEGA_HOOK_SLOT_PATCH)                       ;#6D0A: 3A 03 FA
        ld      c,a                                            ;#6D0D: 4F
        ld      b,4                                            ;#6D0E: 06 04
        dec     hl                                             ;#6D10: 2B
PAGE_PARSE_DIGIT_LOOP:
        ; Per-digit slot parse: skip spaces, read decimal slot
        call    SKIP_SPACES_ADVANCE                            ;#6D11: CD F2 43
        jr      z,PAGE_PARSE_NO_ARGS                           ;#6D14: 28 35
        cp      ","                                            ;#6D16: FE 2C
        jr      z,PAGE_PARSE_NO_DIGIT                          ;#6D18: 28 2E
        sub     "0"                                            ;#6D1A: D6 30
        jp      c,SYNTAX_ERROR_LF                              ;#6D1C: DA 47 43
        cp      4                                              ;#6D1F: FE 04
        jp      nc,SYNTAX_ERROR_LF                             ;#6D21: D2 47 43
        ld      e,a                                            ;#6D24: 5F
        call    SKIP_SPACES_ADVANCE                            ;#6D25: CD F2 43
        jr      nz,PAGE_PARSE_NEED_COMMA                       ;#6D28: 20 03
        dec     hl                                             ;#6D2A: 2B
        jr      PAGE_PARSE_MERGE_SLOT                          ;#6D2B: 18 05

PAGE_PARSE_NEED_COMMA:
        ; After digit — require ',' separator (else syntax error)
        cp      ","                                            ;#6D2D: FE 2C
        jp      nz,SYNTAX_ERROR_LF                             ;#6D2F: C2 47 43
PAGE_PARSE_MERGE_SLOT:
        ; Merge new slot digit (E) into low 2 bits of accumulator C
        ld      a,c                                            ;#6D32: 79
        and     0FCh                                           ;#6D33: E6 FC
        or      e                                              ;#6D35: B3
PAGE_PARSE_ROTATE:
        ; Rotate packed slot byte right 2 bits and loop next digit
        rrca                                                   ;#6D36: 0F
        rrca                                                   ;#6D37: 0F
        ld      c,a                                            ;#6D38: 4F
        djnz    PAGE_PARSE_DIGIT_LOOP                          ;#6D39: 10 D6
PAGE_PARSE_COMMIT:
        ; Mask result to 6 bits, OR with current 0A8h bits 6-7, store
        ld      a,c                                            ;#6D3B: 79
        and     3Fh                                            ;#6D3C: E6 3F
        ld      c,a                                            ;#6D3E: 4F
        in      a,(0A8h)                                       ;#6D3F: DB A8
        and     0C0h                                           ;#6D41: E6 C0
        or      c                                              ;#6D43: B1
        ld      (MEGA_HOOK_SLOT_PATCH),a                       ;#6D44: 32 03 FA
        ret                                                    ;#6D47: C9

PAGE_PARSE_NO_DIGIT:
        ; ',' immediately after ',' — reuse previous slot value (carry through)
        ld      a,c                                            ;#6D48: 79
        jr      PAGE_PARSE_ROTATE                              ;#6D49: 18 EB

PAGE_PARSE_NO_ARGS:
        ; No-arg form — rotate existing MEGA_HOOK_SLOT_PATCH into low bits
        ld      a,c                                            ;#6D4B: 79
PAGE_PARSE_ROTATE_LOOP:
        ; Per-iteration rrca pair body of the no-arg `PAGE ?` rotate path
        rrca                                                   ;#6D4C: 0F
        rrca                                                   ;#6D4D: 0F
        djnz    PAGE_PARSE_ROTATE_LOOP                         ;#6D4E: 10 FC
        ld      c,a                                            ;#6D50: 4F
        jr      PAGE_PARSE_COMMIT                              ;#6D51: 18 E8

MEGA_PCMD_SCR:
        ; Prompt command "SCR start,width,height" — define a sub-window region
        call    SKIP_AND_PARSE_HEX_WORD                        ;#6D53: CD 04 4F
        jp      c,SYNTAX_ERROR_LF                              ;#6D56: DA 47 43
        ld      (MEGA_HEADER_TYPE),de                          ;#6D59: ED 53 30 FA
        ld      a,(hl)                                         ;#6D5D: 7E
        cp      ","                                            ;#6D5E: FE 2C
        jp      nz,SYNTAX_ERROR_LF                             ;#6D60: C2 47 43
        inc     hl                                             ;#6D63: 23
        call    PARSE_HEX_WORD                                 ;#6D64: CD BA 50
        jp      c,SYNTAX_ERROR_LF                              ;#6D67: DA 47 43
        ld      a,e                                            ;#6D6A: 7B
        cp      1Eh                                            ;#6D6B: FE 1E
        jp      nc,SYNTAX_ERROR_LF                             ;#6D6D: D2 47 43
        or      a                                              ;#6D70: B7
        jp      z,SYNTAX_ERROR_LF                              ;#6D71: CA 47 43
        ld      (MEGA_SCRATCH_W3),a                            ;#6D74: 32 34 FA
        ld      (MEGA_SCRATCH_W2_HI),a                         ;#6D77: 32 33 FA
        ld      a,(hl)                                         ;#6D7A: 7E
        cp      ","                                            ;#6D7B: FE 2C
        jp      nz,SYNTAX_ERROR_LF                             ;#6D7D: C2 47 43
        inc     hl                                             ;#6D80: 23
        call    PARSE_HEX_WORD                                 ;#6D81: CD BA 50
        ld      a,e                                            ;#6D84: 7B
        cp      18h                                            ;#6D85: FE 18
        jp      nc,SYNTAX_ERROR_LF                             ;#6D87: D2 47 43
        or      a                                              ;#6D8A: B7
        jp      z,SYNTAX_ERROR_LF                              ;#6D8B: CA 47 43
        ld      (MEGA_SCRATCH_W3_HI),a                         ;#6D8E: 32 35 FA
        ld      (MEGA_SCRATCH_W2),a                            ;#6D91: 32 32 FA
        ld      a,(hl)                                         ;#6D94: 7E
        or      a                                              ;#6D95: B7
        ld      a,1                                            ;#6D96: 3E 01
        jr      z,SCR_INIT_FROM_MODE                           ;#6D98: 28 12
        inc     hl                                             ;#6D9A: 23
        ld      a,(hl)                                         ;#6D9B: 7E
        sub     "0"                                            ;#6D9C: D6 30
        jp      c,SYNTAX_ERROR_LF                              ;#6D9E: DA 47 43
        cp      2                                              ;#6DA1: FE 02
        jp      nc,SYNTAX_ERROR_LF                             ;#6DA3: D2 47 43
        call    SCR_MODE_TO_FLAGS                              ;#6DA6: CD FD 6B
        nop                                                    ;#6DA9: 00
        nop                                                    ;#6DAA: 00
        nop                                                    ;#6DAB: 00
SCR_INIT_FROM_MODE:
        ; After SCR_MODE_TO_FLAGS — store mode, dispatch graphics-or-text init
        ld      (MEGA_EDITOR_MODE_FLAGS),a                     ;#6DAC: 32 36 FA
        ld      a,(MEGA_SCRATCH_W2)                            ;#6DAF: 3A 32 FA
        cp      1                                              ;#6DB2: FE 01
        jr      nz,SCR_INIT_GRAPHICS_MODE                      ;#6DB4: 20 0F
        ld      a,(MEGA_SCRATCH_W2_HI)                         ;#6DB6: 3A 33 FA
        cp      1                                              ;#6DB9: FE 01
        jr      nz,SCR_INIT_GRAPHICS_MODE                      ;#6DBB: 20 08
        ld      a,(MEGA_EDITOR_MODE_FLAGS)                     ;#6DBD: 3A 36 FA
        set     5,a                                            ;#6DC0: CB EF
        ld      (MEGA_EDITOR_MODE_FLAGS),a                     ;#6DC2: 32 36 FA
SCR_INIT_GRAPHICS_MODE:
        ; BIOS_INIGRP + clear VRAM + configure VDP register 1 (E3 01) + sprite setup
        call    BIOS_INIGRP                                    ;#6DC5: CD 72 00
        ld      hl,2000h                                       ;#6DC8: 21 00 20
        ld      bc,1800h                                       ;#6DCB: 01 00 18
        ld      a,0F1h                                         ;#6DCE: 3E F1
        call    BIOS_FILVRM                                    ;#6DD0: CD 56 00
        ld      hl,0                                           ;#6DD3: 21 00 00
        ld      bc,1800h                                       ;#6DD6: 01 00 18
        xor     a                                              ;#6DD9: AF
        call    BIOS_FILVRM                                    ;#6DDA: CD 56 00
SCR_INIT_VDP_R1:
        ; Write VDP R1 = E3h (enable display, mode bits) via WRTVDP
        ld      bc,0E301h                                      ;#6DDD: 01 01 E3
        call    BIOS_WRTVDP                                    ;#6DE0: CD 47 00
        xor     a                                              ;#6DE3: AF
        call    BIOS_CALPAT                                    ;#6DE4: CD 84 00
        ld      de,EDITOR_SPRITE_PATTERNS                      ;#6DE7: 11 E7 6F
        ld      b," "                                          ;#6DEA: 06 20
SCR_INIT_SPRITE_COPY_LOOP:
        ; Copy EDITOR_SPRITE_PATTERNS to VRAM via WRTVRM
        ld      a,(de)                                         ;#6DEC: 1A
        call    BIOS_WRTVRM                                    ;#6DED: CD 4D 00
        inc     hl                                             ;#6DF0: 23
        inc     de                                             ;#6DF1: 13
        djnz    SCR_INIT_SPRITE_COPY_LOOP                      ;#6DF2: 10 F8
        xor     a                                              ;#6DF4: AF
        call    BIOS_CALATR                                    ;#6DF5: CD 87 00
        ld      a,5                                            ;#6DF8: 3E 05
        call    BIOS_WRTVRM                                    ;#6DFA: CD 4D 00
        inc     hl                                             ;#6DFD: 23
        ld      a,0Eh                                          ;#6DFE: 3E 0E
        call    BIOS_WRTVRM                                    ;#6E00: CD 4D 00
        inc     hl                                             ;#6E03: 23
        xor     a                                              ;#6E04: AF
        call    BIOS_WRTVRM                                    ;#6E05: CD 4D 00
        inc     hl                                             ;#6E08: 23
        ld      a,4                                            ;#6E09: 3E 04
        call    BIOS_WRTVRM                                    ;#6E0B: CD 4D 00
EDITOR_KEY_LOOP:
        ; Editor main loop: show cursor → CHGET → dispatch (TAB = End-addr prompt)
        call    EDITOR_RENDER_CURRENT_CELL                     ;#6E0E: CD 5E 70
EDITOR_KEY_WAIT:
        ; Block on BIOS_CHGET for next editor keypress
        call    BIOS_CHGET                                     ;#6E11: CD 9F 00
        cp      9                                              ;#6E14: FE 09
        jr      nz,EDITOR_KEY_DISPATCH                         ;#6E16: 20 66
        call    EDITOR_CLEAR_REGION                            ;#6E18: CD 67 6E
        ld      hl,1618h                                       ;#6E1B: 21 18 16
        ld      hl,0ACh                                        ;#6E1E: 21 AC 00
        ld      (BIOS_GRPACY),hl                               ;#6E21: 22 B9 FC
        ld      hl,18h                                         ;#6E24: 21 18 00
        ld      (BIOS_GRPACX),hl                               ;#6E27: 22 B7 FC
        ld      a,45h                                          ;#6E2A: 3E 45
        call    BIOS_GRPPRT                                    ;#6E2C: CD 8D 00
        ld      a,6Eh                                          ;#6E2F: 3E 6E
        call    BIOS_GRPPRT                                    ;#6E31: CD 8D 00
        ld      a,64h                                          ;#6E34: 3E 64
        call    BIOS_GRPPRT                                    ;#6E36: CD 8D 00
        ld      a,":"                                          ;#6E39: 3E 3A
        call    BIOS_GRPPRT                                    ;#6E3B: CD 8D 00
        ld      hl,(MEGA_HEADER_TYPE)                          ;#6E3E: 2A 30 FA
        ld      a,h                                            ;#6E41: 7C
        call    PRINT_HEX_BYTE_GRPPRT                          ;#6E42: CD 51 6E
        ld      a,l                                            ;#6E45: 7D
        call    PRINT_HEX_BYTE_GRPPRT                          ;#6E46: CD 51 6E
        call    BIOS_CHGET                                     ;#6E49: CD 9F 00
        call    EDITOR_CLEAR_REGION                            ;#6E4C: CD 67 6E
        jr      EDITOR_KEY_LOOP                                ;#6E4F: 18 BD

PRINT_HEX_BYTE_GRPPRT:
        ; Print A as 2 hex digits on the graphics screen via BIOS_GRPPRT
        push    af                                             ;#6E51: F5
        rrca                                                   ;#6E52: 0F
        rrca                                                   ;#6E53: 0F
        rrca                                                   ;#6E54: 0F
        rrca                                                   ;#6E55: 0F
        call    GRPPRT_HEX_NIBBLE                              ;#6E56: CD 5A 6E
        pop     af                                             ;#6E59: F1
GRPPRT_HEX_NIBBLE:
        ; Mask low nibble of A; convert to ASCII '0'..'F'; emit via BIOS_GRPPRT
        and     0Fh                                            ;#6E5A: E6 0F
        cp      0Ah                                            ;#6E5C: FE 0A
        jr      c,GRPPRT_HEX_EMIT                              ;#6E5E: 38 02
        add     a,7                                            ;#6E60: C6 07
GRPPRT_HEX_EMIT:
        ; Common tail — `add a,"0"` then jp BIOS_GRPPRT
        add     a,"0"                                          ;#6E62: C6 30
        jp      BIOS_GRPPRT                                    ;#6E64: C3 8D 00

EDITOR_CLEAR_REGION:
        ; Zero a 3×80 byte region in VRAM at 1510h (editor screen-clear scratch)
        ld      hl,1510h                                       ;#6E67: 21 10 15
        ld      b,3                                            ;#6E6A: 06 03
EDITOR_CLEAR_ROW_LOOP:
        ; Outer per-row loop over 3 rows of 50h VRAM bytes
        push    hl                                             ;#6E6C: E5
        ld      c,50h                                          ;#6E6D: 0E 50
EDITOR_CLEAR_INNER:
        ; Inner per-column body — push BC, xor a, WRTVRM at HL, inc HL, dec C
        push    bc                                             ;#6E6F: C5
        xor     a                                              ;#6E70: AF
        call    BIOS_WRTVRM                                    ;#6E71: CD 4D 00
        inc     hl                                             ;#6E74: 23
        pop     bc                                             ;#6E75: C1
        dec     c                                              ;#6E76: 0D
        jr      nz,EDITOR_CLEAR_INNER                          ;#6E77: 20 F6
        pop     hl                                             ;#6E79: E1
        inc     h                                              ;#6E7A: 24
        djnz    EDITOR_CLEAR_ROW_LOOP                          ;#6E7B: 10 EF
        ret                                                    ;#6E7D: C9

EDITOR_KEY_DISPATCH:
        ; Non-TAB key dispatch: CTRL-C → exit; CTRL-X → toggle bit 6; ESC → palette
        cp      3                                              ;#6E7E: FE 03
        jp      z,BIOS_INITXT                                  ;#6E80: CA 6C 00
        cp      18h                                            ;#6E83: FE 18
        jr      nz,EDITOR_KEY_ESC                              ;#6E85: 20 0B
        ld      a,(MEGA_EDITOR_MODE_FLAGS)                     ;#6E87: 3A 36 FA
        xor     40h                                            ;#6E8A: EE 40
        ld      (MEGA_EDITOR_MODE_FLAGS),a                     ;#6E8C: 32 36 FA
        jp      EDITOR_KEY_LOOP                                ;#6E8F: C3 0E 6E

EDITOR_KEY_ESC:
        ; ESC (1Bh): toggle the colour-attribute byte at sprite slot 0 between D0h/05h
        cp      1Bh                                            ;#6E92: FE 1B
        jr      nz,EDITOR_KEY_CURSOR                           ;#6E94: 20 15
        xor     a                                              ;#6E96: AF
        call    BIOS_CALATR                                    ;#6E97: CD 87 00
        call    BIOS_RDVRM                                     ;#6E9A: CD 4A 00
        cp      5                                              ;#6E9D: FE 05
        ld      a,0D0h                                         ;#6E9F: 3E D0
        jr      z,EDITOR_KEY_ESC_WRITE                         ;#6EA1: 28 02
        ld      a,5                                            ;#6EA3: 3E 05
EDITOR_KEY_ESC_WRITE:
        ; Common WRTVRM tail of ESC arm — write D0h or 05h to sprite-0 attr
        call    BIOS_WRTVRM                                    ;#6EA5: CD 4D 00
        jp      EDITOR_KEY_WAIT                                ;#6EA8: C3 11 6E

EDITOR_KEY_CURSOR:
        ; Cursor-key arm (1Ch-1Fh): compute row*8 offset, dispatch on direction
        ld      de,(MEGA_SCRATCH_W2)                           ;#6EAB: ED 5B 32 FA
        ld      b,d                                            ;#6EAF: 42
        ld      hl,0                                           ;#6EB0: 21 00 00
        ld      d,l                                            ;#6EB3: 55
EDITOR_CURSOR_ROWMUL_LOOP:
        ; Multiply HL+=DE B times to compute row*8 offset
        add     hl,de                                          ;#6EB4: 19
        djnz    EDITOR_CURSOR_ROWMUL_LOOP                      ;#6EB5: 10 FD
        add     hl,hl                                          ;#6EB7: 29
        add     hl,hl                                          ;#6EB8: 29
        add     hl,hl                                          ;#6EB9: 29
        ex      de,hl                                          ;#6EBA: EB
        ld      hl,(MEGA_HEADER_TYPE)                          ;#6EBB: 2A 30 FA
        cp      1Ch                                            ;#6EBE: FE 1C
        jr      nz,CURSOR_TEST_RIGHT                           ;#6EC0: 20 01
        inc     hl                                             ;#6EC2: 23
CURSOR_TEST_RIGHT:
        ; Test for 1Dh (right) — dec HL if matched
        cp      1Dh                                            ;#6EC3: FE 1D
        jr      nz,CURSOR_TEST_UP                              ;#6EC5: 20 01
        dec     hl                                             ;#6EC7: 2B
CURSOR_TEST_UP:
        ; Test for 1Eh (up) — `sbc hl,de` (back one row) if matched
        cp      1Eh                                            ;#6EC8: FE 1E
        jr      nz,CURSOR_TEST_DOWN                            ;#6ECA: 20 03
        and     a                                              ;#6ECC: A7
        sbc     hl,de                                          ;#6ECD: ED 52
CURSOR_TEST_DOWN:
        ; Test for 1Fh (down) — `add hl,de` (forward one row) if matched
        cp      1Fh                                            ;#6ECF: FE 1F
        jr      nz,CURSOR_COMMIT                               ;#6ED1: 20 01
        add     hl,de                                          ;#6ED3: 19
CURSOR_COMMIT:
        ; Common commit — store new HL into MEGA_HEADER_TYPE (cursor pos)
        ld      (MEGA_HEADER_TYPE),hl                          ;#6ED4: 22 30 FA
        cp      0Dh                                            ;#6ED7: FE 0D
        jp      nz,EDITOR_KEY_LOOP                             ;#6ED9: C2 0E 6E
        ld      a,(MEGA_EDITOR_MODE_FLAGS)                     ;#6EDC: 3A 36 FA
        bit     5,a                                            ;#6EDF: CB 6F
        jp      nz,EDITOR_BLIT_8X23_BLOCK                      ;#6EE1: C2 C4 6F
        and     40h                                            ;#6EE4: E6 40
        jp      z,EDITOR_NEW_CELL_SETUP                        ;#6EE6: CA 85 6F
        ld      hl,(MEGA_HEADER_TYPE)                          ;#6EE9: 2A 30 FA
        ld      de,MEGA_EDITOR_CELL_BUF                        ;#6EEC: 11 3C FA
        ld      bc,10h                                         ;#6EEF: 01 10 00
        call    MEGA_SLOT_LDIR                                 ;#6EF2: CD 22 FA
        ld      a,(MEGA_SCRATCH_W2)                            ;#6EF5: 3A 32 FA
        ld      l,a                                            ;#6EF8: 6F
        ld      h,0                                            ;#6EF9: 26 00
        add     hl,hl                                          ;#6EFB: 29
        add     hl,hl                                          ;#6EFC: 29
        add     hl,hl                                          ;#6EFD: 29
        ld      (MEGA_EDITOR_ROW_OFF),hl                       ;#6EFE: 22 5C FA
        ld      bc,(MEGA_HEADER_TYPE)                          ;#6F01: ED 4B 30 FA
        add     hl,bc                                          ;#6F05: 09
        ld      bc,10h                                         ;#6F06: 01 10 00
        call    MEGA_SLOT_LDIR                                 ;#6F09: CD 22 FA
EDITOR_EDIT_LOADED_CELL:
        ; Point DATA_BASE at MEGA_EDITOR_CELL_BUF, set up VDP, enter key-input loop
        ld      hl,MEGA_EDITOR_CELL_BUF                        ;#6F0C: 21 3C FA
        ld      (MEGA_EDITOR_DATA_BASE),hl                     ;#6F0F: 22 3A FA
        call    EDITOR_SETUP_VDP                               ;#6F12: CD 8C 71
        call    EDITOR_KEY_INPUT                               ;#6F15: CD A2 72
        push    af                                             ;#6F18: F5
        ld      hl,770h                                        ;#6F19: 21 70 07
        ld      b,10h                                          ;#6F1C: 06 10
EDITOR_FILL_BLOCK_LOOP:
        ; Fill 10h pages of 80h VRAM bytes for editor clear
        push    bc                                             ;#6F1E: C5
        push    hl                                             ;#6F1F: E5
        ld      bc,80h                                         ;#6F20: 01 80 00
        xor     a                                              ;#6F23: AF
        call    BIOS_FILVRM                                    ;#6F24: CD 56 00
        pop     hl                                             ;#6F27: E1
        pop     bc                                             ;#6F28: C1
        inc     h                                              ;#6F29: 24
        djnz    EDITOR_FILL_BLOCK_LOOP                         ;#6F2A: 10 F2
        pop     af                                             ;#6F2C: F1
        cp      3                                              ;#6F2D: FE 03
        jr      z,EDITOR_REINIT_SCREEN                         ;#6F2F: 28 29
        ld      a,(MEGA_EDITOR_MODE_FLAGS)                     ;#6F31: 3A 36 FA
        ld      de,(MEGA_HEADER_TYPE)                          ;#6F34: ED 5B 30 FA
        ld      hl,MEGA_EDITOR_CELL_BUF                        ;#6F38: 21 3C FA
        ld      bc,10h                                         ;#6F3B: 01 10 00
        bit     5,a                                            ;#6F3E: CB 6F
        jp      nz,EDITOR_BLIT_SET8_RESTART                    ;#6F40: C2 DF 6F
        and     40h                                            ;#6F43: E6 40
        jr      z,EDITOR_GRP1_8COPY                            ;#6F45: 28 16
        call    MEGA_SLOT_LDIR                                 ;#6F47: CD 22 FA
        ld      bc,(MEGA_EDITOR_ROW_OFF)                       ;#6F4A: ED 4B 5C FA
        ex      de,hl                                          ;#6F4E: EB
        ld      hl,(MEGA_HEADER_TYPE)                          ;#6F4F: 2A 30 FA
        add     hl,bc                                          ;#6F52: 09
        ex      de,hl                                          ;#6F53: EB
        ld      bc,10h                                         ;#6F54: 01 10 00
        call    MEGA_SLOT_LDIR                                 ;#6F57: CD 22 FA
EDITOR_REINIT_SCREEN:
        ; jp into SCR_INIT_GRAPHICS_MODE at 6DDD — reinit VDP, sprites, patterns
        jp      SCR_INIT_VDP_R1                                ;#6F5A: C3 DD 6D

EDITOR_GRP1_8COPY:
        ; Non-bit-6 (single-cell) arm — LDIR 8 bytes + 3× COPY_8_FROM_HEADER_BASE
        ld      c,8                                            ;#6F5D: 0E 08
        call    MEGA_SLOT_LDIR                                 ;#6F5F: CD 22 FA
        ld      bc,(MEGA_EDITOR_ROW_OFF)                       ;#6F62: ED 4B 5C FA
        call    COPY_8_FROM_HEADER_BASE                        ;#6F66: CD 78 6F
        ld      bc,8                                           ;#6F69: 01 08 00
        call    COPY_8_FROM_HEADER_BASE                        ;#6F6C: CD 78 6F
        ld      bc,(MEGA_EDITOR_COL_OFF)                       ;#6F6F: ED 4B 5E FA
        call    COPY_8_FROM_HEADER_BASE                        ;#6F73: CD 78 6F
        jr      EDITOR_REINIT_SCREEN                           ;#6F76: 18 E2

COPY_8_FROM_HEADER_BASE:
        ; LDIR 8 bytes from (MEGA_HEADER_TYPE)+BC into DE (slot-aware)
        ex      de,hl                                          ;#6F78: EB
        ld      hl,(MEGA_HEADER_TYPE)                          ;#6F79: 2A 30 FA
        add     hl,bc                                          ;#6F7C: 09
        ex      de,hl                                          ;#6F7D: EB
        ld      bc,8                                           ;#6F7E: 01 08 00
        call    MEGA_SLOT_LDIR                                 ;#6F81: CD 22 FA
        ret                                                    ;#6F84: C9

EDITOR_NEW_CELL_SETUP:
        ; CR-on-cell-paint arm — LDIR 8-byte glyph and compute row offset from W3
        ld      hl,(MEGA_HEADER_TYPE)                          ;#6F85: 2A 30 FA
        ld      de,MEGA_EDITOR_CELL_BUF                        ;#6F88: 11 3C FA
        ld      bc,8                                           ;#6F8B: 01 08 00
        call    MEGA_SLOT_LDIR                                 ;#6F8E: CD 22 FA
        ld      a,(MEGA_SCRATCH_W3)                            ;#6F91: 3A 34 FA
        ld      l,a                                            ;#6F94: 6F
        ld      h,0                                            ;#6F95: 26 00
        add     hl,hl                                          ;#6F97: 29
        add     hl,hl                                          ;#6F98: 29
        add     hl,hl                                          ;#6F99: 29
        ld      (MEGA_EDITOR_ROW_OFF),hl                       ;#6F9A: 22 5C FA
        ld      bc,(MEGA_HEADER_TYPE)                          ;#6F9D: ED 4B 30 FA
        push    hl                                             ;#6FA1: E5
        add     hl,bc                                          ;#6FA2: 09
        push    hl                                             ;#6FA3: E5
        ld      bc,8                                           ;#6FA4: 01 08 00
        call    MEGA_SLOT_LDIR                                 ;#6FA7: CD 22 FA
        ld      hl,(MEGA_HEADER_TYPE)                          ;#6FAA: 2A 30 FA
        ld      c,8                                            ;#6FAD: 0E 08
        add     hl,bc                                          ;#6FAF: 09
        call    MEGA_SLOT_LDIR                                 ;#6FB0: CD 22 FA
        pop     hl                                             ;#6FB3: E1
        ld      c,8                                            ;#6FB4: 0E 08
        add     hl,bc                                          ;#6FB6: 09
        call    MEGA_SLOT_LDIR                                 ;#6FB7: CD 22 FA
        ld      c,8                                            ;#6FBA: 0E 08
        pop     hl                                             ;#6FBC: E1
        add     hl,bc                                          ;#6FBD: 09
        ld      (MEGA_EDITOR_COL_OFF),hl                       ;#6FBE: 22 5E FA
        jp      EDITOR_EDIT_LOADED_CELL                        ;#6FC1: C3 0C 6F

EDITOR_BLIT_8X23_BLOCK:
        ; CR-on-cell-paint bit-5 arm — LDIR 8 bytes glyph + 23 bytes of zeros
        ld      hl,(MEGA_HEADER_TYPE)                          ;#6FC4: 2A 30 FA
        ld      de,MEGA_EDITOR_CELL_BUF                        ;#6FC7: 11 3C FA
        ld      bc,8                                           ;#6FCA: 01 08 00
        call    MEGA_SLOT_LDIR                                 ;#6FCD: CD 22 FA
        ex      de,hl                                          ;#6FD0: EB
        ld      (hl),0                                         ;#6FD1: 36 00
        push    hl                                             ;#6FD3: E5
        pop     de                                             ;#6FD4: D1
        inc     de                                             ;#6FD5: 13
        ld      bc,17h                                         ;#6FD6: 01 17 00
        call    MEGA_SLOT_LDIR                                 ;#6FD9: CD 22 FA
        jp      EDITOR_EDIT_LOADED_CELL                        ;#6FDC: C3 0C 6F

EDITOR_BLIT_SET8_RESTART:
        ; Set BC=8 then LDIR + jp REINIT_SCREEN — common 8-byte tail
        ld      c,8                                            ;#6FDF: 0E 08
        call    MEGA_SLOT_LDIR                                 ;#6FE1: CD 22 FA
        jp      EDITOR_REINIT_SCREEN                           ;#6FE4: C3 5A 6F

EDITOR_SPRITE_PATTERNS:
        ; 16x16 sprite — 10×10 hollow-frame cell cursor (top/bottom edge + sides)
        ; Format: FORMAT_BITMAP_SPRITE
        ; - Each pair of 16 bytes is a sprite half (8 cols x 16 rows). Rendered
        ; - as raw hex because the bit layout is geometric, not Z80 instruction-shaped.
        dh      "FF8080808080808080FF000000000000"             ;#6FE7: FF 80 80 80 80 80 80 80 80 FF 00 00 00 00 00 00
        dh      "C04040404040404040C0000000000000"             ;#6FF7: C0 40 40 40 40 40 40 40 40 C0 00 00 00 00 00 00

EDITOR_BLIT_GLYPHS_TO_VRAM:
        ; Blit a B×C run of MEGA_EDITOR_CELL_BUF glyph rows to VRAM via OUT (98h)
        ld      a,(MEGA_EDITOR_MODE_FLAGS)                     ;#7007: 3A 36 FA
        bit     6,a                                            ;#700A: CB 77
        jr      nz,EDITOR_BLIT_GLYPHS_DOUBLE                   ;#700C: 20 26
EDITOR_BLIT_ROW_LOOP:
        ; Per-row body: push BC/HL, SETWRT, LDIR glyph, OUT 8 bytes, advance H/C
        push    bc                                             ;#700E: C5
        push    hl                                             ;#700F: E5
        call    BIOS_SETWRT                                    ;#7010: CD 53 00
        di                                                     ;#7013: F3
EDITOR_BLIT_ROW_OUTER_LOOP:
        ; Glyph blit: SETWRT/LDIR/8-byte OUT row loop
        push    bc                                             ;#7014: C5
        ex      de,hl                                          ;#7015: EB
        ld      bc,8                                           ;#7016: 01 08 00
        ld      de,MEGA_EDITOR_CELL_BUF                        ;#7019: 11 3C FA
        push    de                                             ;#701C: D5
        call    MEGA_SLOT_LDIR                                 ;#701D: CD 22 FA
        ex      de,hl                                          ;#7020: EB
        pop     hl                                             ;#7021: E1
        ld      b,8                                            ;#7022: 06 08
EDITOR_BLIT_ROW_BYTE_LOOP:
        ; Inner 8x out (98h) loop for one glyph row
        ld      a,(hl)                                         ;#7024: 7E
        out     (98h),a                                        ;#7025: D3 98
        inc     hl                                             ;#7027: 23
        djnz    EDITOR_BLIT_ROW_BYTE_LOOP                      ;#7028: 10 FA
        pop     bc                                             ;#702A: C1
        djnz    EDITOR_BLIT_ROW_OUTER_LOOP                     ;#702B: 10 E7
        pop     hl                                             ;#702D: E1
        pop     bc                                             ;#702E: C1
        inc     h                                              ;#702F: 24
        dec     c                                              ;#7030: 0D
        jr      nz,EDITOR_BLIT_ROW_LOOP                        ;#7031: 20 DB
        ret                                                    ;#7033: C9

EDITOR_BLIT_GLYPHS_DOUBLE:
        ; Alternate blit used when MEGA_EDITOR_MODE_FLAGS bit 6 (double-height) is set
        push    bc                                             ;#7034: C5
        push    hl                                             ;#7035: E5
EDITOR_BLIT_DOUBLE_ROW_LOOP:
        ; Double-height per-row push+LDIR loop top
        push    bc                                             ;#7036: C5
        push    hl                                             ;#7037: E5
        call    BIOS_SETWRT                                    ;#7038: CD 53 00
        ex      de,hl                                          ;#703B: EB
        ld      bc,8                                           ;#703C: 01 08 00
        ld      de,MEGA_EDITOR_CELL_BUF                        ;#703F: 11 3C FA
        push    de                                             ;#7042: D5
        call    MEGA_SLOT_LDIR                                 ;#7043: CD 22 FA
        ex      de,hl                                          ;#7046: EB
        pop     hl                                             ;#7047: E1
        ld      b,8                                            ;#7048: 06 08
EDITOR_BLIT_DOUBLE_BYTE_LOOP:
        ; Double-height inner 8x out (98h) byte loop
        ld      a,(hl)                                         ;#704A: 7E
        out     (98h),a                                        ;#704B: D3 98
        inc     hl                                             ;#704D: 23
        djnz    EDITOR_BLIT_DOUBLE_BYTE_LOOP                   ;#704E: 10 FA
        pop     hl                                             ;#7050: E1
        pop     bc                                             ;#7051: C1
        inc     h                                              ;#7052: 24
        djnz    EDITOR_BLIT_DOUBLE_ROW_LOOP                    ;#7053: 10 E1
        pop     hl                                             ;#7055: E1
        ld      c,8                                            ;#7056: 0E 08
        add     hl,bc                                          ;#7058: 09
        pop     bc                                             ;#7059: C1
        dec     c                                              ;#705A: 0D
        jr      nz,EDITOR_BLIT_GLYPHS_DOUBLE                   ;#705B: 20 D7
        ret                                                    ;#705D: C9

EDITOR_RENDER_CURRENT_CELL:
        ; Render the active editor cell to VRAM at 110h via EDITOR_BLIT_GLYPHS_TO_VRAM
        ld      hl,110h                                        ;#705E: 21 10 01
        ld      de,(MEGA_HEADER_TYPE)                          ;#7061: ED 5B 30 FA
EDITOR_DRAW_ROW:
        ; Outer per-row drawing loop — push row addr then dispatch to per-cell blit
        push    hl                                             ;#7065: E5
EDITOR_DRAW_CELL:
        ; Inner per-cell loop body — blit current cell, advance horizontal position
        push    hl                                             ;#7066: E5
        ld      bc,(MEGA_SCRATCH_W2)                           ;#7067: ED 4B 32 FA
        ld      a,(MEGA_EDITOR_MODE_FLAGS)                     ;#706B: 3A 36 FA
        bit     6,a                                            ;#706E: CB 77
        jr      z,EDITOR_DRAW_BLIT_CALL                        ;#7070: 28 04
        ld      bc,(MEGA_SCRATCH_W3)                           ;#7072: ED 4B 34 FA
EDITOR_DRAW_BLIT_CALL:
        ; Common arm — call EDITOR_BLIT_GLYPHS_TO_VRAM with W2 or W3 cells
        call    EDITOR_BLIT_GLYPHS_TO_VRAM                     ;#7076: CD 07 70
        pop     hl                                             ;#7079: E1
        ld      a,(MEGA_SCRATCH_W3)                            ;#707A: 3A 34 FA
        push    af                                             ;#707D: F5
        add     a,a                                            ;#707E: 87
        add     a,a                                            ;#707F: 87
        add     a,a                                            ;#7080: 87
        add     a,l                                            ;#7081: 85
        ld      l,a                                            ;#7082: 6F
        pop     af                                             ;#7083: F1
        add     a,a                                            ;#7084: 87
        jr      c,EDITOR_DRAW_NEXT_ROW                         ;#7085: 38 0D
        add     a,a                                            ;#7087: 87
        jr      c,EDITOR_DRAW_NEXT_ROW                         ;#7088: 38 0A
        add     a,a                                            ;#708A: 87
        jr      c,EDITOR_DRAW_NEXT_ROW                         ;#708B: 38 07
        add     a,l                                            ;#708D: 85
        jr      c,EDITOR_DRAW_NEXT_ROW                         ;#708E: 38 04
        add     a,8                                            ;#7090: C6 08
        jr      nc,EDITOR_DRAW_CELL                            ;#7092: 30 D2
EDITOR_DRAW_NEXT_ROW:
        ; Row overflow: pop saved HL, advance V by (FA35), wrap if past row 23
        pop     hl                                             ;#7094: E1
        ld      a,(MEGA_SCRATCH_W3_HI)                         ;#7095: 3A 35 FA
        push    af                                             ;#7098: F5
        add     a,h                                            ;#7099: 84
        ld      h,a                                            ;#709A: 67
        pop     af                                             ;#709B: F1
        add     a,h                                            ;#709C: 84
        cp      18h                                            ;#709D: FE 18
        jr      c,EDITOR_DRAW_ROW                              ;#709F: 38 C4
        ret                                                    ;#70A1: C9

EDITOR_DRAW_HEADER:
        ; Draw editor header in VRAM 1B00 + VDP register: mode-aware cursor/mode indicator
        ld      a,(MEGA_DM_OFFSET)                             ;#70A2: 3A 38 FA
        add     a,a                                            ;#70A5: 87
        add     a,a                                            ;#70A6: 87
        add     a,a                                            ;#70A7: 87
        dec     a                                              ;#70A8: 3D
        ld      b,0                                            ;#70A9: 06 00
        ld      c,a                                            ;#70AB: 4F
        call    EDITOR_MODE_TEST_LO                            ;#70AC: CD 84 73
        ld      a,c                                            ;#70AF: 79
        jr      z,EDITOR_DRAW_HEADER_WRITE                     ;#70B0: 28 04
        add     a,38h                                          ;#70B2: C6 38
        ld      b,60h                                          ;#70B4: 06 60
EDITOR_DRAW_HEADER_WRITE:
        ; Common WRTVRM tail — write char to header at VRAM 1B00h
        ld      hl,1B00h                                       ;#70B6: 21 00 1B
        call    BIOS_WRTVRM                                    ;#70B9: CD 4D 00
        ld      a,(DM_ZAP_MODE)                                ;#70BC: 3A 37 FA
        add     a,a                                            ;#70BF: 87
        add     a,a                                            ;#70C0: 87
        add     a,a                                            ;#70C1: 87
        add     a,10h                                          ;#70C2: C6 10
        add     a,b                                            ;#70C4: 80
        jp      WRITE_VDP_DATA_PORT                            ;#70C5: C3 87 71

COMPUTE_EDITOR_DATA_ADDR:
        ; HL = MEGA_EDITOR_DATA_BASE + cursor_pos*8 when in sub-mode; else base only
        call    EDITOR_MODE_TEST_LO                            ;#70C8: CD 84 73
        jr      z,COMPUTE_EDITOR_DATA_BODY                     ;#70CB: 28 04
        ld      hl,(MEGA_EDITOR_DATA_BASE)                     ;#70CD: 2A 3A FA
        ret                                                    ;#70D0: C9

COMPUTE_EDITOR_DATA_BODY:
        ; Sub-mode arm — HL = base + cursor*8
        ld      a,(MEGA_EDITOR_CURSOR_POS)                     ;#70D1: 3A 39 FA
        ld      l,a                                            ;#70D4: 6F
        ld      h,0                                            ;#70D5: 26 00
        add     hl,hl                                          ;#70D7: 29
        add     hl,hl                                          ;#70D8: 29
        add     hl,hl                                          ;#70D9: 29
        ld      de,(MEGA_EDITOR_DATA_BASE)                     ;#70DA: ED 5B 3A FA
        add     hl,de                                          ;#70DE: 19
        ret                                                    ;#70DF: C9

COMPUTE_CURSOR_COLOR_ADDR:
        ; Build HL = colour-table VRAM addr for cursor cell, from MEGA_EDITOR_CURSOR_POS
        ld      a,(MEGA_EDITOR_CURSOR_POS)                     ;#70E0: 3A 39 FA
        push    af                                             ;#70E3: F5
        and     0Fh                                            ;#70E4: E6 0F
        add     a,a                                            ;#70E6: 87
        add     a,a                                            ;#70E7: 87
        add     a,a                                            ;#70E8: 87
        add     a,60h                                          ;#70E9: C6 60
        ld      l,a                                            ;#70EB: 6F
        pop     af                                             ;#70EC: F1
        rlca                                                   ;#70ED: 07
        rlca                                                   ;#70EE: 07
        rlca                                                   ;#70EF: 07
        rlca                                                   ;#70F0: 07
        and     0Fh                                            ;#70F1: E6 0F
        add     a,8                                            ;#70F3: C6 08
        ld      h,a                                            ;#70F5: 67
        ret                                                    ;#70F6: C9

EDITOR_REDRAW_DATA:
        ; Copy current data buffer to VRAM (pattern or color table) — refresh after edit
        call    COMPUTE_EDITOR_DATA_ADDR                       ;#70F7: CD C8 70
        ex      de,hl                                          ;#70FA: EB
        call    EDITOR_MODE_TEST_LO                            ;#70FB: CD 84 73
        ld      hl,10h                                         ;#70FE: 21 10 00
        jr      nz,EDITOR_REDRAW_GRAPHIC2                      ;#7101: 20 07
        ld      b,8                                            ;#7103: 06 08
        call    VRAM_WRITE_VERT_LOOP                           ;#7105: CD 1A 71
        jr      EDITOR_REFRESH_COLOR                           ;#7108: 18 1D

EDITOR_REDRAW_GRAPHIC2:
        ; SCREEN-2 path: write 16-byte runs at VRAM 770h and 7B0h
        ld      hl,770h                                        ;#710A: 21 70 07
        call    VRAM_WRITE_VERT16                              ;#710D: CD 18 71
        ld      hl,7B0h                                        ;#7110: 21 B0 07
        call    VRAM_WRITE_VERT16                              ;#7113: CD 18 71
        jr      EDITOR_REFRESH_COLOR                           ;#7116: 18 0F

VRAM_WRITE_VERT16:
        ; Write 16 bytes (DE) → VRAM at HL with +256 stride per byte (vertical run)
        ld      b,10h                                          ;#7118: 06 10
VRAM_WRITE_VERT_LOOP:
        ; Loop body of VRAM_WRITE_VERT* — caller-supplied B byte count, +256 stride
        call    BIOS_SETWRT                                    ;#711A: CD 53 00
        ld      a,(de)                                         ;#711D: 1A
        exx                                                    ;#711E: D9
        call    EDITOR_EXPAND_BYTE_TO_VRAM                     ;#711F: CD 52 71
        exx                                                    ;#7122: D9
        inc     h                                              ;#7123: 24
        inc     de                                             ;#7124: 13
        djnz    VRAM_WRITE_VERT_LOOP                           ;#7125: 10 F3
EDITOR_REFRESH_COLOR:
        ; Post-pattern-redraw: if editor active + bit 7 set, refresh colour table at 480h
        call    EDITOR_MODE_TEST_LO                            ;#7127: CD 84 73
        ret     nz                                             ;#712A: C0
        ld      a,(MEGA_EDITOR_MODE_FLAGS)                     ;#712B: 3A 36 FA
        bit     7,a                                            ;#712E: CB 7F
        ret     z                                              ;#7130: C8
        call    COMPUTE_EDITOR_DATA_ADDR                       ;#7131: CD C8 70
        ld      de,480h                                        ;#7134: 11 80 04
        ld      bc,8                                           ;#7137: 01 08 00
        call    BIOS_LDIRVM                                    ;#713A: CD 5C 00
        call    COMPUTE_CURSOR_COLOR_ADDR                      ;#713D: CD E0 70
        push    hl                                             ;#7140: E5
        call    COMPUTE_EDITOR_DATA_ADDR                       ;#7141: CD C8 70
        pop     de                                             ;#7144: D1
        ex      de,hl                                          ;#7145: EB
        ld      b,8                                            ;#7146: 06 08
EDITOR_REFRESH_COLOR_LOOP:
        ; Per-byte 8x colour-table refresh via WRTVRM_INVERT
        ld      a,(de)                                         ;#7148: 1A
        nop                                                    ;#7149: 00
        call    EDITOR_WRTVRM_INVERT                           ;#714A: CD 05 6C
        inc     hl                                             ;#714D: 23
        inc     de                                             ;#714E: 13
        djnz    EDITOR_REFRESH_COLOR_LOOP                      ;#714F: 10 F7
        ret                                                    ;#7151: C9

EDITOR_EXPAND_BYTE_TO_VRAM:
        ; Expand 8 bits of A into a 9-byte fg/bg VRAM write — pattern-magnify trick
        ld      c,a                                            ;#7152: 4F
        ld      b,8                                            ;#7153: 06 08
EDITOR_EXPAND_BIT_LOOP:
        ; Per-bit expand: 8 iterations rotating C into VDP
        xor     a                                              ;#7155: AF
        rl      c                                              ;#7156: CB 11
        jr      nc,EDITOR_EXPAND_BIT_BG                        ;#7158: 30 01
        cpl                                                    ;#715A: 2F
EDITOR_EXPAND_BIT_BG:
        ; Pixel-bit OFF arm — bg colour (E=0), proceed to VDP-write sequence
        ld      e,a                                            ;#715B: 5F
        ld      a,0FFh                                         ;#715C: 3E FF
        xor     e                                              ;#715E: AB
        call    WRITE_VDP_DATA_PORT                            ;#715F: CD 87 71
        ld      a,81h                                          ;#7162: 3E 81
        xor     e                                              ;#7164: AB
        push    bc                                             ;#7165: C5
        ld      b,6                                            ;#7166: 06 06
EDITOR_EXPAND_FILL_LOOP:
        ; 6x WRITE_VDP_DATA_PORT fill within bit-expand
        call    WRITE_VDP_DATA_PORT                            ;#7168: CD 87 71
        djnz    EDITOR_EXPAND_FILL_LOOP                        ;#716B: 10 FB
        pop     bc                                             ;#716D: C1
        ld      a,0FFh                                         ;#716E: 3E FF
        xor     e                                              ;#7170: AB
        call    WRITE_VDP_DATA_PORT                            ;#7171: CD 87 71
        djnz    EDITOR_EXPAND_BIT_LOOP                         ;#7174: 10 DF
        ret                                                    ;#7176: C9

TOGGLE_CURSOR_COLOR:
        ; Flip 8 colour-table bytes at the editor cursor cell — visible cursor blink
        call    COMPUTE_CURSOR_COLOR_ADDR                      ;#7177: CD E0 70
        ld      b,8                                            ;#717A: 06 08
TOGGLE_CURSOR_COLOR_LOOP:
        ; 8x RDVRM/cpl/WRTVRM cursor-cell colour flip
        call    BIOS_RDVRM                                     ;#717C: CD 4A 00
        cpl                                                    ;#717F: 2F
        call    BIOS_WRTVRM                                    ;#7180: CD 4D 00
        inc     hl                                             ;#7183: 23
        djnz    TOGGLE_CURSOR_COLOR_LOOP                       ;#7184: 10 F6
        ret                                                    ;#7186: C9

WRITE_VDP_DATA_PORT:
        ; `out (98h),a / nop / nop / ret` — write byte to VDP data port with timing pad
        out     (98h),a                                        ;#7187: D3 98
        nop                                                    ;#7189: 00
        nop                                                    ;#718A: 00
        ret                                                    ;#718B: C9

EDITOR_SETUP_VDP:
        ; Programme VDP for the editor (R1=E0h, clear name/colour tables, draw frame)
        ld      hl,0                                           ;#718C: 21 00 00
        ld      (DM_ZAP_MODE),hl                               ;#718F: 22 37 FA
        ld      bc,0E001h                                      ;#7192: 01 01 E0
        call    BIOS_WRTVDP                                    ;#7195: CD 47 00
        ld      hl,3800h                                       ;#7198: 21 00 38
        ld      a,0FFh                                         ;#719B: 3E FF
        call    BIOS_WRTVRM                                    ;#719D: CD 4D 00
        call    WRITE_VDP_DATA_PORT                            ;#71A0: CD 87 71
        ld      a,0C3h                                         ;#71A3: 3E C3
        ld      b,4                                            ;#71A5: 06 04
EDITOR_SETUP_VDP_FILL_LOOP:
        ; 4x out C3h fill of name-table top after WRTVRM
        call    WRITE_VDP_DATA_PORT                            ;#71A7: CD 87 71
        djnz    EDITOR_SETUP_VDP_FILL_LOOP                     ;#71AA: 10 FB
        ld      a,0FFh                                         ;#71AC: 3E FF
        call    WRITE_VDP_DATA_PORT                            ;#71AE: CD 87 71
        call    WRITE_VDP_DATA_PORT                            ;#71B1: CD 87 71
        ld      hl,1B02h                                       ;#71B4: 21 02 1B
        ld      a,0                                            ;#71B7: 3E 00
        call    BIOS_WRTVRM                                    ;#71B9: CD 4D 00
        ld      a,9                                            ;#71BC: 3E 09
        call    WRITE_VDP_DATA_PORT                            ;#71BE: CD 87 71
        call    EDITOR_DRAW_HEADER                             ;#71C1: CD A2 70
        jp      EDITOR_REDRAW_DATA                             ;#71C4: C3 F7 70

MEGA_CMD_EDITOR:
        ; `CALL EDITOR` — switch VDP to graphics mode and enter the full-screen editor
        pop     hl                                             ;#71C7: E1
        call    SKIP_SPACES                                    ;#71C8: CD F3 43
        call    PARSE_EDITOR_DATA_BASE                         ;#71CB: CD 26 6C
        jr      z,EDITOR_FROM_BASE                             ;#71CE: 28 0B
        ld      ix,BIOS_EVAL_BASIC_OPERAND                     ;#71D0: DD 21 2F 54
        call    BIOS_CALBAS                                    ;#71D4: CD 59 01
        call    SKIP_SPACES                                    ;#71D7: CD F3 43
        nop                                                    ;#71DA: 00
EDITOR_FROM_BASE:
        ; After data-base parsed — push HL, save DE→DATA_BASE, init graphics mode
        push    hl                                             ;#71DB: E5
        ld      (MEGA_EDITOR_DATA_BASE),de                     ;#71DC: ED 53 3A FA
        call    BIOS_INIGRP                                    ;#71E0: CD 72 00
        ld      a,80h                                          ;#71E3: 3E 80
        ld      (MEGA_EDITOR_MODE_FLAGS),a                     ;#71E5: 32 36 FA
        call    EDITOR_SETUP_VDP                               ;#71E8: CD 8C 71
        ld      b,8                                            ;#71EB: 06 08
        ld      hl,2010h                                       ;#71ED: 21 10 20
EDITOR_SETUP_VDP_TILE_LOOP:
        ; 8x FILVRM 40h-byte tiles into VRAM 2010h+
        push    bc                                             ;#71F0: C5
        push    hl                                             ;#71F1: E5
        ld      a,0F1h                                         ;#71F2: 3E F1
        ld      bc,40h                                         ;#71F4: 01 40 00
        call    BIOS_FILVRM                                    ;#71F7: CD 56 00
        pop     hl                                             ;#71FA: E1
        pop     bc                                             ;#71FB: C1
        inc     h                                              ;#71FC: 24
        djnz    EDITOR_SETUP_VDP_TILE_LOOP                     ;#71FD: 10 F1
        ld      hl,2800h                                       ;#71FF: 21 00 28
        ld      bc,1000h                                       ;#7202: 01 00 10
        ld      a,0F1h                                         ;#7205: 3E F1
        call    BIOS_FILVRM                                    ;#7207: CD 56 00
EDITOR_REDRAW_ROWS:
        ; Re-init data rows: load DATA_BASE, LDIRVM 16x80h to VRAM
        ld      hl,(MEGA_EDITOR_DATA_BASE)                     ;#720A: 2A 3A FA
        ld      de,860h                                        ;#720D: 11 60 08
        ld      a,10h                                          ;#7210: 3E 10
EDITOR_ROW_INIT_LOOP:
        ; Per-row init body — push AF/DE/HL, LDIR 80h bytes via BIOS_LDIRVM
        push    af                                             ;#7212: F5
        push    de                                             ;#7213: D5
        push    hl                                             ;#7214: E5
        ld      bc,80h                                         ;#7215: 01 80 00
        call    BIOS_LDIRVM                                    ;#7218: CD 5C 00
        ld      c,80h                                          ;#721B: 0E 80
        pop     hl                                             ;#721D: E1
        add     hl,bc                                          ;#721E: 09
        pop     de                                             ;#721F: D1
        pop     af                                             ;#7220: F1
        inc     d                                              ;#7221: 14
        dec     a                                              ;#7222: 3D
        jr      nz,EDITOR_ROW_INIT_LOOP                        ;#7223: 20 ED
        ld      hl,2480h                                       ;#7225: 21 80 24
        ld      bc,8                                           ;#7228: 01 08 00
        ld      a,0F4h                                         ;#722B: 3E F4
        call    BIOS_FILVRM                                    ;#722D: CD 56 00
        xor     a                                              ;#7230: AF
        ld      (MEGA_EDITOR_INVERT),a                         ;#7231: 32 74 FA
        ld      (MEGA_EDITOR_CURSOR_POS),a                     ;#7234: 32 39 FA
        call    EDITOR_REDRAW_DATA                             ;#7237: CD F7 70
        call    TOGGLE_CURSOR_COLOR                            ;#723A: CD 77 71
EDITOR_KEY_INPUT_NOREV:
        ; Editor key wait (no cursor invert): CHGET, dispatch on cursor keys + entry
        xor     a                                              ;#723D: AF
        ld      (MEGA_EDITOR_INVERT),a                         ;#723E: 32 74 FA
        call    BIOS_CHGET                                     ;#7241: CD 9F 00
        ld      hl,MEGA_EDITOR_CURSOR_POS                      ;#7244: 21 39 FA
        ld      c,(hl)                                         ;#7247: 4E
        cp      1Ch                                            ;#7248: FE 1C
        jr      c,EDITOR_KEY_NOREV_NORM                        ;#724A: 38 04
        cp      " "                                            ;#724C: FE 20
        jr      c,EDITOR_KEY_NOREV_CURSOR                      ;#724E: 38 28
EDITOR_KEY_NOREV_NORM:
        ; Range-gate path: CTL-L (0Ch)? = clear data buf via LDIR from 1BBFh
        cp      0Ch                                            ;#7250: FE 0C
        jr      nz,EDITOR_KEY_NOREV_CTRL                       ;#7252: 20 0E
        ld      hl,1BBFh                                       ;#7254: 21 BF 1B
        ld      de,(MEGA_EDITOR_DATA_BASE)                     ;#7257: ED 5B 3A FA
        ld      bc,800h                                        ;#725B: 01 00 08
        ldir                                                   ;#725E: ED B0
        jr      EDITOR_REDRAW_ROWS                             ;#7260: 18 A8

EDITOR_KEY_NOREV_CTRL:
        ; Control-key arm: TAB/CTRL-C = exit, CR = enter inner key wait
        cp      9                                              ;#7262: FE 09
        jp      z,POP_AND_RETURN_NC                            ;#7264: CA 8B 73
        cp      3                                              ;#7267: FE 03
        jp      z,POP_AND_RETURN_NC                            ;#7269: CA 8B 73
        cp      0Dh                                            ;#726C: FE 0D
        call    z,EDITOR_KEY_INPUT                             ;#726E: CC A2 72
        cp      3                                              ;#7271: FE 03
        jp      z,POP_AND_RETURN_NC                            ;#7273: CA 8B 73
        jr      EDITOR_KEY_INPUT_NOREV                         ;#7276: 18 C5

EDITOR_KEY_NOREV_CURSOR:
        ; Cursor-key arm: 1C/1D/1E/1F → C=+1/-1/-16/+16 offsets
        cp      1Ch                                            ;#7278: FE 1C
        jr      nz,EDITOR_KEY_NOREV_RIGHT                      ;#727A: 20 02
        ld      c,1                                            ;#727C: 0E 01
EDITOR_KEY_NOREV_RIGHT:
        ; 1Dh (right) — C=FFh (-1 wrap)
        cp      1Dh                                            ;#727E: FE 1D
        jr      nz,EDITOR_KEY_NOREV_UP                         ;#7280: 20 02
        ld      c,0FFh                                         ;#7282: 0E FF
EDITOR_KEY_NOREV_UP:
        ; 1Eh (up) — C=F0h (-16)
        cp      1Eh                                            ;#7284: FE 1E
        jr      nz,EDITOR_KEY_NOREV_DOWN                       ;#7286: 20 02
        ld      c,0F0h                                         ;#7288: 0E F0
EDITOR_KEY_NOREV_DOWN:
        ; 1Fh (down) — C=10h (+16)
        cp      1Fh                                            ;#728A: FE 1F
        jr      nz,EDITOR_KEY_NOREV_APPLY                      ;#728C: 20 02
        ld      c,10h                                          ;#728E: 0E 10
EDITOR_KEY_NOREV_APPLY:
        ; Apply C-offset to cursor pos, redraw, refresh cursor highlight, loop
        ld      a,(hl)                                         ;#7290: 7E
        add     a,c                                            ;#7291: 81
        push    af                                             ;#7292: F5
        call    TOGGLE_CURSOR_COLOR                            ;#7293: CD 77 71
        pop     af                                             ;#7296: F1
        ld      (MEGA_EDITOR_CURSOR_POS),a                     ;#7297: 32 39 FA
        call    EDITOR_REDRAW_DATA                             ;#729A: CD F7 70
        call    TOGGLE_CURSOR_COLOR                            ;#729D: CD 77 71
        jr      EDITOR_KEY_INPUT_NOREV                         ;#72A0: 18 9B

EDITOR_KEY_INPUT:
        ; Editor inner key wait: enable invert cursor, CHGET, compute data addr, dispatch
        ld      a,1                                            ;#72A2: 3E 01
        ld      (MEGA_EDITOR_INVERT),a                         ;#72A4: 32 74 FA
        call    BIOS_CHGET                                     ;#72A7: CD 9F 00
        push    af                                             ;#72AA: F5
        call    COMPUTE_EDITOR_DATA_ADDR                       ;#72AB: CD C8 70
        call    EDITOR_MODE_TEST_LO                            ;#72AE: CD 84 73
        ld      b,8                                            ;#72B1: 06 08
        jr      z,EDITOR_KEY_INPUT_DECIDE                      ;#72B3: 28 02
        ld      b," "                                          ;#72B5: 06 20
EDITOR_KEY_INPUT_DECIDE:
        ; After invert + CHGET — pop key, test for CR/CTRL-C/space
        pop     af                                             ;#72B7: F1
        cp      0Dh                                            ;#72B8: FE 0D
        ret     z                                              ;#72BA: C8
        cp      3                                              ;#72BB: FE 03
        ret     z                                              ;#72BD: C8
        cp      " "                                            ;#72BE: FE 20
        jr      nz,EDITOR_CMD_INVERT                           ;#72C0: 20 26
        ld      a,(DM_ZAP_MODE)                                ;#72C2: 3A 37 FA
        ld      e,0                                            ;#72C5: 1E 00
        ld      b,8                                            ;#72C7: 06 08
        bit     3,a                                            ;#72C9: CB 5F
        jr      z,EDITOR_KEY_INPUT_PIXEL                       ;#72CB: 28 02
        ld      e,10h                                          ;#72CD: 1E 10
EDITOR_KEY_INPUT_PIXEL:
        ; Pixel-toggle path — compute bit position from DM_ZAP_MODE
        ld      a,(MEGA_DM_OFFSET)                             ;#72CF: 3A 38 FA
        add     a,e                                            ;#72D2: 83
        ld      e,a                                            ;#72D3: 5F
        ld      d,0                                            ;#72D4: 16 00
        add     hl,de                                          ;#72D6: 19
        ld      a,(DM_ZAP_MODE)                                ;#72D7: 3A 37 FA
        ld      b,a                                            ;#72DA: 47
        ld      a,8                                            ;#72DB: 3E 08
        sub     b                                              ;#72DD: 90
        ld      b,a                                            ;#72DE: 47
        ld      a,80h                                          ;#72DF: 3E 80
EDITOR_KEY_PIXEL_RLCA_LOOP:
        ; rlca A B times to align bit mask for pixel toggle
        rlca                                                   ;#72E1: 07
        djnz    EDITOR_KEY_PIXEL_RLCA_LOOP                     ;#72E2: 10 FD
        xor     (hl)                                           ;#72E4: AE
        ld      (hl),a                                         ;#72E5: 77
        jr      EDITOR_AFTER_KEY                               ;#72E6: 18 64

EDITOR_CMD_INVERT:
        ; 'I' command — `cpl` each of 8 bytes in the current row (invert all bits)
        cp      "I"                                            ;#72E8: FE 49
        jr      nz,EDITOR_CMD_CLEAR                            ;#72EA: 20 08
EDITOR_CMD_INVERT_LOOP:
        ; Per-byte cpl over 8 row bytes ('I' command)
        ld      a,(hl)                                         ;#72EC: 7E
        cpl                                                    ;#72ED: 2F
        ld      (hl),a                                         ;#72EE: 77
        inc     hl                                             ;#72EF: 23
        djnz    EDITOR_CMD_INVERT_LOOP                         ;#72F0: 10 FA
        jr      EDITOR_AFTER_KEY                               ;#72F2: 18 58

EDITOR_CMD_CLEAR:
        ; 0Ch (CTRL-L) — zero each of 8 bytes in the row
        cp      0Ch                                            ;#72F4: FE 0C
        jr      nz,EDITOR_CMD_SHIFT                            ;#72F6: 20 07
        xor     a                                              ;#72F8: AF
EDITOR_CMD_CLEAR_LOOP:
        ; Per-byte zero-fill over 8 row bytes (CTRL-L)
        ld      (hl),a                                         ;#72F9: 77
        inc     hl                                             ;#72FA: 23
        djnz    EDITOR_CMD_CLEAR_LOOP                          ;#72FB: 10 FC
        jr      EDITOR_AFTER_KEY                               ;#72FD: 18 4D

EDITOR_CMD_SHIFT:
        ; 'S' command — shift in arrow direction (RR/RL/up/down rotate) over 8 bytes
        cp      "S"                                            ;#72FF: FE 53
        jr      nz,EDITOR_DM_NAV_INIT                          ;#7301: 20 4F
        call    COMPUTE_EDITOR_DATA_ADDR                       ;#7303: CD C8 70
        ld      b,8                                            ;#7306: 06 08
        call    EDITOR_MODE_TEST_LO                            ;#7308: CD 84 73
        jr      nz,EDITOR_AFTER_KEY                            ;#730B: 20 3F
        call    BIOS_CHGET                                     ;#730D: CD 9F 00
        cp      1Ch                                            ;#7310: FE 1C
        jr      nz,EDITOR_SHIFT_RIGHT                          ;#7312: 20 07
EDITOR_SHIFT_LEFT_LOOP:
        ; rrc (hl) over 8 row bytes (left-arrow shift)
        rrc     (hl)                                           ;#7314: CB 0E
        inc     hl                                             ;#7316: 23
        djnz    EDITOR_SHIFT_LEFT_LOOP                         ;#7317: 10 FB
        jr      EDITOR_AFTER_KEY                               ;#7319: 18 31

EDITOR_SHIFT_RIGHT:
        ; 1Dh arm — rlc each row byte (left shift, wrap into high bit)
        cp      1Dh                                            ;#731B: FE 1D
        jr      nz,EDITOR_SHIFT_UP                             ;#731D: 20 07
EDITOR_SHIFT_RIGHT_LOOP:
        ; rlc (hl) over 8 row bytes (right-arrow shift)
        rlc     (hl)                                           ;#731F: CB 06
        inc     hl                                             ;#7321: 23
        djnz    EDITOR_SHIFT_RIGHT_LOOP                        ;#7322: 10 FB
        jr      EDITOR_AFTER_KEY                               ;#7324: 18 26

EDITOR_SHIFT_UP:
        ; 1Eh arm — LDIR-up rotate (row 0 stashed, rows shift up, restored at bottom)
        cp      1Eh                                            ;#7326: FE 1E
        jr      nz,EDITOR_SHIFT_DOWN                           ;#7328: 20 0E
        push    hl                                             ;#732A: E5
        pop     de                                             ;#732B: D1
        ld      a,(hl)                                         ;#732C: 7E
        push    af                                             ;#732D: F5
        inc     hl                                             ;#732E: 23
        ld      bc,7                                           ;#732F: 01 07 00
        ldir                                                   ;#7332: ED B0
        pop     af                                             ;#7334: F1
        ld      (de),a                                         ;#7335: 12
        jr      EDITOR_AFTER_KEY                               ;#7336: 18 14

EDITOR_SHIFT_DOWN:
        ; 1Fh arm — LDDR-down rotate (last row stashed, rows shift down, restored at top)
        cp      1Fh                                            ;#7338: FE 1F
        jp      nz,EDITOR_KEY_INPUT                            ;#733A: C2 A2 72
        ld      bc,7                                           ;#733D: 01 07 00
        add     hl,bc                                          ;#7340: 09
        push    hl                                             ;#7341: E5
        pop     de                                             ;#7342: D1
        ld      a,(hl)                                         ;#7343: 7E
        dec     hl                                             ;#7344: 2B
        push    af                                             ;#7345: F5
        lddr                                                   ;#7346: ED B8
        pop     af                                             ;#7348: F1
        ld      (de),a                                         ;#7349: 12
        jr      EDITOR_AFTER_KEY                               ;#734A: 18 00

EDITOR_AFTER_KEY:
        ; Per-key tail: call EDITOR_REDRAW_DATA + jp 72A2 — return to key-input loop
        call    EDITOR_REDRAW_DATA                             ;#734C: CD F7 70
        jp      EDITOR_KEY_INPUT                               ;#734F: C3 A2 72

EDITOR_DM_NAV_INIT:
        ; 'M' command — clear BC, dispatch on arrow key to ±1 (DM_ZAP_MODE)
        ld      bc,0                                           ;#7352: 01 00 00
        cp      1Ch                                            ;#7355: FE 1C
        jr      nz,EDITOR_DM_NAV_RIGHT                         ;#7357: 20 01
        inc     c                                              ;#7359: 0C
EDITOR_DM_NAV_RIGHT:
        ; 1Dh — dec C (right wraparound)
        cp      1Dh                                            ;#735A: FE 1D
        jr      nz,EDITOR_DM_NAV_UP                            ;#735C: 20 01
        dec     c                                              ;#735E: 0D
EDITOR_DM_NAV_UP:
        ; 1Eh — dec B (one row up)
        cp      1Eh                                            ;#735F: FE 1E
        jr      nz,EDITOR_DM_NAV_DOWN                          ;#7361: 20 01
        dec     b                                              ;#7363: 05
EDITOR_DM_NAV_DOWN:
        ; 1Fh — inc B (one row down)
        cp      1Fh                                            ;#7364: FE 1F
        jr      nz,EDITOR_DM_NAV_APPLY                         ;#7366: 20 01
        inc     b                                              ;#7368: 04
EDITOR_DM_NAV_APPLY:
        ; Apply BC delta with mask E (7 or 15) and store into DM_ZAP_MODE
        call    EDITOR_MODE_TEST_LO                            ;#7369: CD 84 73
        ld      e,7                                            ;#736C: 1E 07
        jr      z,EDITOR_DM_NAV_STORE                          ;#736E: 28 02
        ld      e,0Fh                                          ;#7370: 1E 0F
EDITOR_DM_NAV_STORE:
        ; Per-byte store of new B/C masked into the offset bytes
        ld      hl,DM_ZAP_MODE                                 ;#7372: 21 37 FA
        ld      a,(hl)                                         ;#7375: 7E
        add     a,c                                            ;#7376: 81
        and     e                                              ;#7377: A3
        ld      (hl),a                                         ;#7378: 77
        inc     hl                                             ;#7379: 23
        ld      a,(hl)                                         ;#737A: 7E
        add     a,b                                            ;#737B: 80
        and     e                                              ;#737C: A3
        ld      (hl),a                                         ;#737D: 77
        call    EDITOR_DRAW_HEADER                             ;#737E: CD A2 70
        jp      EDITOR_KEY_INPUT                               ;#7381: C3 A2 72

EDITOR_MODE_TEST_LO:
        ; Load MEGA_EDITOR_MODE_FLAGS, mask off bit 7, set flags; Z if low 7 bits zero
        ld      a,(MEGA_EDITOR_MODE_FLAGS)                     ;#7384: 3A 36 FA
        and     7Fh                                            ;#7387: E6 7F
        or      a                                              ;#7389: B7
        ret                                                    ;#738A: C9

POP_AND_RETURN_NC:
        ; `pop hl / and a / ret` — discard caller, return to grandparent with CF=0
        pop     hl                                             ;#738B: E1
        and     a                                              ;#738C: A7
        ret                                                    ;#738D: C9

MEGA_PCMD_DM:
        ; Prompt command "DM start[,end]" — Display Memory (FA37=0, fall through)
        xor     a                                              ;#738E: AF
        ld      (DM_ZAP_MODE),a                                ;#738F: 32 37 FA
        jr      DM_ZAP_BODY                                    ;#7392: 18 05

MEGA_PCMD_ZAP:
        ; Prompt command "ZAP start[,end]" — Zap (clear) memory (FA37=1, fall)
        ld      a,1                                            ;#7394: 3E 01
        ld      (DM_ZAP_MODE),a                                ;#7396: 32 37 FA
DM_ZAP_BODY:
        ; Shared body — parse start/end, then display or zap based on FA37 flag
        call    SKIP_SPACES                                    ;#7399: CD F3 43
        jp      z,SYNTAX_ERROR_LF                              ;#739C: CA 47 43
        call    PARSE_HEX_WORD                                 ;#739F: CD BA 50
        ld      (MEGA_HEADER_TYPE),de                          ;#73A2: ED 53 30 FA
        call    CHECK_DM_ZAP_MODE                              ;#73A6: CD B2 76
        jr      z,DM_ZAP_PARSE_OFFSET                          ;#73A9: 28 04
        ld      (MEGA_SCRATCH_W3),de                           ;#73AB: ED 53 34 FA
DM_ZAP_PARSE_OFFSET:
        ; After end addr — check next char: 0=no-offset, ','=offset arg
        ld      a,(hl)                                         ;#73AF: 7E
        or      a                                              ;#73B0: B7
        jr      z,MEGA_PCMD_DM_STORE_OFFSET                    ;#73B1: 28 18
        cp      ","                                            ;#73B3: FE 2C
        jp      nz,SYNTAX_ERROR_LF                             ;#73B5: C2 47 43
        inc     hl                                             ;#73B8: 23
        ld      a,(hl)                                         ;#73B9: 7E
        push    af                                             ;#73BA: F5
        cp      "-"                                            ;#73BB: FE 2D
        jr      nz,DM_ZAP_PARSE_OFFSET_VAL                     ;#73BD: 20 01
        inc     hl                                             ;#73BF: 23
DM_ZAP_PARSE_OFFSET_VAL:
        ; Negative offset arm — parse hex word for the magnitude
        call    PARSE_HEX_WORD_AND_EOL                         ;#73C0: CD E1 43
        pop     af                                             ;#73C3: F1
        cp      "-"                                            ;#73C4: FE 2D
        ld      a,e                                            ;#73C6: 7B
        jr      nz,MEGA_PCMD_DM_STORE_OFFSET                   ;#73C7: 20 02
        neg                                                    ;#73C9: ED 44
MEGA_PCMD_DM_STORE_OFFSET:
        ; Store final offset value (signed `-N`) into MEGA_DM_OFFSET and continue setup
        ld      (MEGA_DM_OFFSET),a                             ;#73CB: 32 38 FA
        call    BIOS_CLEAR_SCREEN                              ;#73CE: CD 77 07
        ld      hl,112h                                        ;#73D1: 21 12 01
        call    BIOS_POSIT                                     ;#73D4: CD C6 00
        call    CHECK_DM_ZAP_MODE                              ;#73D7: CD B2 76
        jr      nz,DM_HEADER_OFFSET                            ;#73DA: 20 0E
        call    PRINT_INLINE_STRING                            ;#73DC: CD 8A 50
        db      "Endereco:"C                                   ;#73DF: 45 6E 64 65 72 65 63 6F BA
        jr      DM_HEADER_OFFSET_TAIL                          ;#73E8: 18 0C

DM_HEADER_OFFSET:
        ; OffSet header — print "OffSet:" prefix for the ZAP variant
        call    PRINT_INLINE_STRING                            ;#73EA: CD 8A 50
        db      "OffSet  :"C                                   ;#73ED: 4F 66 66 53 65 74 20 20 BA

DM_HEADER_OFFSET_TAIL:
        ; DM header tail entry: zap-check after Endereco prompt
        call    CHECK_DM_ZAP_MODE                              ;#73F6: CD B2 76
        jr      z,DM_HEADER_TAIL                               ;#73F9: 28 11
        ld      a," "                                          ;#73FB: 3E 20
        ld      b,5                                            ;#73FD: 06 05
DM_HEADER_TRACK_PAD_LOOP:
        ; 5x rst 18h space pad before "Trilha:" label
        rst     18h                                            ;#73FF: DF
        djnz    DM_HEADER_TRACK_PAD_LOOP                       ;#7400: 10 FD
        call    PRINT_INLINE_STRING                            ;#7402: CD 8A 50
        db      "Trilha:"C                                     ;#7405: 54 72 69 6C 68 61 BA

DM_HEADER_TAIL:
        ; Common header tail — print CR + "Desloc.:" + sign + offset hex
        call    PRINT_CR                                       ;#740C: CD B4 42
        call    PRINT_INLINE_STRING                            ;#740F: CD 8A 50
        db      "Desloc.:"C                                    ;#7412: 44 65 73 6C 6F 63 2E BA
        ld      a,(MEGA_DM_OFFSET)                             ;#741A: 3A 38 FA
        cp      80h                                            ;#741D: FE 80
        ld      a,"-"                                          ;#741F: 3E 2D
        jr      nc,DM_PRINT_OFFSET_SIGN                        ;#7421: 30 02
        ld      a,"+"                                          ;#7423: 3E 2B

DM_PRINT_OFFSET_SIGN:
        ; Common arm — RST 18h (PRINT_CHAR) emit the +/- sign
        rst     18h                                            ;#7425: DF
        ld      a,(MEGA_DM_OFFSET)                             ;#7426: 3A 38 FA
        cp      80h                                            ;#7429: FE 80
        jr      c,DM_PRINT_OFFSET_VALUE                        ;#742B: 38 02
        neg                                                    ;#742D: ED 44

DM_PRINT_OFFSET_VALUE:
        ; Print absolute value of offset in hex after the sign
        call    PRINT_HEX_A                                    ;#742F: CD A3 50
        xor     a                                              ;#7432: AF
        ld      (MEGA_EDITOR_MODE_FLAGS),a                     ;#7433: 32 36 FA
        ld      h,a                                            ;#7436: 67
        ld      l,a                                            ;#7437: 6F
        ld      (MEGA_SCRATCH_W2),hl                           ;#7438: 22 32 FA
        call    CHECK_DM_ZAP_MODE                              ;#743B: CD B2 76
        jr      z,DM_INIT_AND_REDRAW                           ;#743E: 28 03
        ld      (MEGA_HEADER_TYPE),hl                          ;#7440: 22 30 FA
DM_INIT_AND_REDRAW:
        ; DM/ZAP entry: CHECK_DM_ZAP_MODE; if ZAP, prep PHYDIO buffer (764F); paint screen
        call    CHECK_DM_ZAP_MODE                              ;#7443: CD B2 76
        call    nz,DISK_PHYDIO_READ                            ;#7446: C4 4F 76
DM_REDRAW_AND_LOOP:
        ; Re-entry after a state-change key: re-DM_DRAW_FULL_PAGE then back into DM_LOOP
        call    DM_DRAW_FULL_PAGE                              ;#7449: CD D7 75
DM_LOOP:
        ; DM main loop: redraw via EDITOR_DISPLAY_ADDR, BIOS_CHGET, handle key
        call    EDITOR_DISPLAY_ADDR                            ;#744C: CD 26 76
        call    BIOS_CHGET                                     ;#744F: CD 9F 00
        cp      18h                                            ;#7452: FE 18
        jr      nz,DM_KEY_CR                                   ;#7454: 20 0A
        ld      a,(MEGA_EDITOR_MODE_FLAGS)                     ;#7456: 3A 36 FA
        xor     1                                              ;#7459: EE 01
        ld      (MEGA_EDITOR_MODE_FLAGS),a                     ;#745B: 32 36 FA
        jr      DM_LOOP                                        ;#745E: 18 EC

DM_KEY_CR:
        ; CR key (0Dh) — reposition cursor at (1,14h) and return
        cp      0Dh                                            ;#7460: FE 0D
        jp      nz,DM_KEY_W                                    ;#7462: C2 6C 74
        ld      hl,114h                                        ;#7465: 21 14 01
        call    BIOS_POSIT                                     ;#7468: CD C6 00
        ret                                                    ;#746B: C9

DM_KEY_W:
        ; 17h (CTRL-W) key — ZAP mode: PHYDIO write then redraw
        cp      17h                                            ;#746C: FE 17
        jr      nz,DM_KEY_ESC                                  ;#746E: 20 0A
        call    CHECK_DM_ZAP_MODE                              ;#7470: CD B2 76
        jr      z,DM_KEY_ESC                                   ;#7473: 28 05
        call    DISK_PHYDIO_WRITE                              ;#7475: CD 5F 76
        jr      DM_REDRAW_AND_LOOP                             ;#7478: 18 CF

DM_KEY_ESC:
        ; ESC key (1Bh) — page back: HEADER_TYPE -= 80h, prompt save when needed
        cp      1Bh                                            ;#747A: FE 1B
        jr      nz,DM_KEY_TAB                                  ;#747C: 20 27
DM_KEY_ESC_PAGEBACK:
        ; Subtract 80h from HEADER_TYPE for ESC page-back logic
        ld      hl,(MEGA_HEADER_TYPE)                          ;#747E: 2A 30 FA
        ld      de,80h                                         ;#7481: 11 80 00
        sbc     hl,de                                          ;#7484: ED 52
        ld      (MEGA_HEADER_TYPE),hl                          ;#7486: 22 30 FA
        jr      nc,DM_REDRAW_AND_LOOP                          ;#7489: 30 BE
        call    CHECK_DM_ZAP_MODE                              ;#748B: CD B2 76
        jr      z,DM_REDRAW_AND_LOOP                           ;#748E: 28 B9
        ld      h,1                                            ;#7490: 26 01
        ld      (MEGA_HEADER_TYPE),hl                          ;#7492: 22 30 FA
        call    EDITOR_PROMPT_SAVE                             ;#7495: CD B7 76
        ld      hl,(MEGA_SCRATCH_W3)                           ;#7498: 2A 34 FA
        ld      a,h                                            ;#749B: 7C
        or      l                                              ;#749C: B5
        jr      z,DM_INIT_AND_REDRAW                           ;#749D: 28 A4
        dec     hl                                             ;#749F: 2B
        ld      (MEGA_SCRATCH_W3),hl                           ;#74A0: 22 34 FA
        jr      DM_INIT_AND_REDRAW                             ;#74A3: 18 9E

DM_KEY_TAB:
        ; 09h (TAB) key — page forward (+80h to HEADER_TYPE)
        cp      9                                              ;#74A5: FE 09
        jr      nz,DM_KEY_ARROW_DISPATCH                       ;#74A7: 20 27
DM_KEY_PAGEFWD:
        ; Page-forward entry: add 80h to HEADER_TYPE, refresh
        ld      hl,(MEGA_HEADER_TYPE)                          ;#74A9: 2A 30 FA
        ld      de,80h                                         ;#74AC: 11 80 00
        add     hl,de                                          ;#74AF: 19
        ld      (MEGA_HEADER_TYPE),hl                          ;#74B0: 22 30 FA
        call    CHECK_DM_ZAP_MODE                              ;#74B3: CD B2 76
        jr      z,DM_REDRAW_AND_LOOP                           ;#74B6: 28 91
        ld      de,200h                                        ;#74B8: 11 00 02
        rst     20h                                            ;#74BB: E7
        jr      c,DM_REDRAW_AND_LOOP                           ;#74BC: 38 8B
        ld      h,0                                            ;#74BE: 26 00
        ld      (MEGA_HEADER_TYPE),hl                          ;#74C0: 22 30 FA
        call    EDITOR_PROMPT_SAVE                             ;#74C3: CD B7 76
        ld      hl,(MEGA_SCRATCH_W3)                           ;#74C6: 2A 34 FA
        inc     hl                                             ;#74C9: 23
        ld      (MEGA_SCRATCH_W3),hl                           ;#74CA: 22 34 FA
        jp      DM_INIT_AND_REDRAW                             ;#74CD: C3 43 74

DM_KEY_ARROW_DISPATCH:
        ; Arrow-key dispatch gate: range-check 1Ch..1Fh
        cp      1Ch                                            ;#74D0: FE 1C
        jp      c,DM_KEY_OTHER                                 ;#74D2: DA 26 75
        cp      " "                                            ;#74D5: FE 20
        jp      nc,DM_KEY_OTHER                                ;#74D7: D2 26 75
        ld      hl,(MEGA_SCRATCH_W2)                           ;#74DA: 2A 32 FA
        ld      de,0                                           ;#74DD: 11 00 00
        cp      1Ch                                            ;#74E0: FE 1C
        jr      nz,DM_ARROW_TRY_LEFT                           ;#74E2: 20 01
        inc     d                                              ;#74E4: 14
DM_ARROW_TRY_LEFT:
        ; Test for 1Dh (left) — d -= 1 on match
        cp      1Dh                                            ;#74E5: FE 1D
        jr      nz,DM_ARROW_TRY_UP                             ;#74E7: 20 01
        dec     d                                              ;#74E9: 15
DM_ARROW_TRY_UP:
        ; Test for 1Eh (up) — e -= 1 on match
        cp      1Eh                                            ;#74EA: FE 1E
        jr      nz,DM_ARROW_TRY_DOWN                           ;#74EC: 20 01
        dec     e                                              ;#74EE: 1D
DM_ARROW_TRY_DOWN:
        ; Test for 1Fh (down) — e += 1 on match
        cp      1Fh                                            ;#74EF: FE 1F
        jr      nz,DM_APPLY_CURSOR_DELTA                       ;#74F1: 20 01
        inc     e                                              ;#74F3: 1C
DM_APPLY_CURSOR_DELTA:
        ; After arrow-key dispatch — apply d/e position deltas to scratch (h,l)
        ld      a,h                                            ;#74F4: 7C
        add     a,d                                            ;#74F5: 82
        ld      h,a                                            ;#74F6: 67
        cp      0FFh                                           ;#74F7: FE FF
        jr      nz,DM_CURSOR_ROW_WRAP_HI                       ;#74F9: 20 03
        ld      h,7                                            ;#74FB: 26 07
        dec     l                                              ;#74FD: 2D
DM_CURSOR_ROW_WRAP_HI:
        ; Row underflow check — H==FF wraps to row 7, dec col
        cp      8                                              ;#74FE: FE 08
        jr      nz,DM_CURSOR_COL_APPLY                         ;#7500: 20 03
        ld      h,0                                            ;#7502: 26 00
        inc     l                                              ;#7504: 2C
DM_CURSOR_COL_APPLY:
        ; Apply E delta to column L, then check underflow
        ld      a,l                                            ;#7505: 7D
        add     a,e                                            ;#7506: 83
        ld      l,a                                            ;#7507: 6F
        cp      0FFh                                           ;#7508: FE FF
        jr      nz,DM_CURSOR_COL_WRAP_HI                       ;#750A: 20 08
        ld      l,0Fh                                          ;#750C: 2E 0F
        ld      (MEGA_SCRATCH_W2),hl                           ;#750E: 22 32 FA
        jp      DM_KEY_ESC_PAGEBACK                            ;#7511: C3 7E 74

DM_CURSOR_COL_WRAP_HI:
        ; Col overflow check — L==10h wraps col to 0, next page
        cp      10h                                            ;#7514: FE 10
        jr      nz,DM_CURSOR_COMMIT                            ;#7516: 20 08
        ld      l,0                                            ;#7518: 2E 00
        ld      (MEGA_SCRATCH_W2),hl                           ;#751A: 22 32 FA
        jp      DM_KEY_PAGEFWD                                 ;#751D: C3 A9 74

DM_CURSOR_COMMIT:
        ; Store cursor (HL) to SCRATCH_W2 and back to DM_LOOP
        ld      (MEGA_SCRATCH_W2),hl                           ;#7520: 22 32 FA
        jp      DM_LOOP                                        ;#7523: C3 4C 74

DM_KEY_OTHER:
        ; Non-cursor, non-special key — fall into hex-digit data-entry path
        ld      de,(MEGA_SCRATCH_W2)                           ;#7526: ED 5B 32 FA
        push    de                                             ;#752A: D5
        push    af                                             ;#752B: F5
        call    DM_FETCH_AT_ROW_COL                            ;#752C: CD C5 75
        pop     bc                                             ;#752F: C1
        pop     de                                             ;#7530: D1
        ld      a,(MEGA_EDITOR_MODE_FLAGS)                     ;#7531: 3A 36 FA
        or      a                                              ;#7534: B7
        ld      a,b                                            ;#7535: 78
        jr      nz,DM_PARSE_HEX_INPUT                          ;#7536: 20 18
        cp      " "                                            ;#7538: FE 20
        jp      c,DM_LOOP                                      ;#753A: DA 4C 74
        cp      7Fh                                            ;#753D: FE 7F
        jp      z,DM_LOOP                                      ;#753F: CA 4C 74
DM_COMMIT_BYTE:
        ; Write the (just-typed) byte at HL via DM_WRITE_BYTE, refresh display, advance
        call    DM_WRITE_BYTE                                  ;#7542: CD 96 76
        push    de                                             ;#7545: D5
        call    EDITOR_DISPLAY_ADDR                            ;#7546: CD 26 76
        pop     hl                                             ;#7549: E1
        ld      de,100h                                        ;#754A: 11 00 01
        jp      DM_APPLY_CURSOR_DELTA                          ;#754D: C3 F4 74

DM_PARSE_HEX_INPUT:
        ; Parse first hex nibble, shift, CHGET 2nd, OR, commit
        call    PARSE_HEX_CHAR_UPPER                           ;#7550: CD 68 75
        jp      c,DM_LOOP                                      ;#7553: DA 4C 74
        rlca                                                   ;#7556: 07
        rlca                                                   ;#7557: 07
        rlca                                                   ;#7558: 07
        rlca                                                   ;#7559: 07
        push    af                                             ;#755A: F5
        call    BIOS_CHGET                                     ;#755B: CD 9F 00
        pop     bc                                             ;#755E: C1
        call    PARSE_HEX_CHAR_UPPER                           ;#755F: CD 68 75
        jp      c,DM_LOOP                                      ;#7562: DA 4C 74
        or      b                                              ;#7565: B0
        jr      DM_COMMIT_BYTE                                 ;#7566: 18 DA

PARSE_HEX_CHAR_UPPER:
        ; Parse uppercase hex char '0'..'9'/'A'..'F' → 0..15; CF=1 if invalid
        ld      c,a                                            ;#7568: 4F
        sub     "0"                                            ;#7569: D6 30
        ret     c                                              ;#756B: D8
        cp      0Ah                                            ;#756C: FE 0A
        jr      c,PARSE_HEX_CHAR_ECHO                          ;#756E: 38 0B
        sub     7                                              ;#7570: D6 07
        cp      0Ah                                            ;#7572: FE 0A
        ret     c                                              ;#7574: D8
        cp      10h                                            ;#7575: FE 10
        jr      c,PARSE_HEX_CHAR_ECHO                          ;#7577: 38 02
        scf                                                    ;#7579: 37
        ret                                                    ;#757A: C9

PARSE_HEX_CHAR_ECHO:
        ; Valid-digit success tail: clear CF, echo char via BIOS_CHPUT, ret
        and     a                                              ;#757B: A7
        push    af                                             ;#757C: F5
        ld      a,c                                            ;#757D: 79
        call    BIOS_CHPUT                                     ;#757E: CD A2 00
        pop     af                                             ;#7581: F1
        ret                                                    ;#7582: C9

DM_DRAW_HEX_CELL:
        ; Redraw the hex column of one DM/ZAP cell (row=H, col=L) via DM_FETCH_AT_ROW_COL
        ld      a,h                                            ;#7583: 7C
        add     a,a                                            ;#7584: 87
        add     a,h                                            ;#7585: 84
        add     a,6                                            ;#7586: C6 06
        push    hl                                             ;#7588: E5
        ld      h,a                                            ;#7589: 67
        inc     l                                              ;#758A: 2C
        call    BIOS_POSIT                                     ;#758B: CD C6 00
        pop     de                                             ;#758E: D1
        call    DM_FETCH_AT_ROW_COL                            ;#758F: CD C5 75
        call    PRINT_HEX_A                                    ;#7592: CD A3 50
        ld      a,8                                            ;#7595: 3E 08
        call    BIOS_CHPUT                                     ;#7597: CD A2 00
        jp      BIOS_CHPUT                                     ;#759A: C3 A2 00

DM_DRAW_ASCII_CELL:
        ; Redraw the ASCII column (offset 1Eh) of one DM/ZAP cell; non-printable → '.'
        ld      a,h                                            ;#759D: 7C
        add     a,1Eh                                          ;#759E: C6 1E
        push    hl                                             ;#75A0: E5
        ld      h,a                                            ;#75A1: 67
        inc     l                                              ;#75A2: 2C
        inc     h                                              ;#75A3: 24
        call    BIOS_POSIT                                     ;#75A4: CD C6 00
        pop     de                                             ;#75A7: D1
        call    DM_FETCH_AT_ROW_COL                            ;#75A8: CD C5 75
        cp      7Fh                                            ;#75AB: FE 7F
        jr      nz,DM_ASCII_TEST_SPACE                         ;#75AD: 20 02
        ld      a,"."                                          ;#75AF: 3E 2E
DM_ASCII_TEST_SPACE:
        ; ASCII < 0x20 → render as '.'
        cp      " "                                            ;#75B1: FE 20
        jr      nc,DM_ASCII_TEST_FF                            ;#75B3: 30 02
        ld      a,"."                                          ;#75B5: 3E 2E
DM_ASCII_TEST_FF:
        ; ASCII == 0xFF → render as '.'
        cp      0FFh                                           ;#75B7: FE FF
        jr      nz,DM_ASCII_CELL_EMIT                          ;#75B9: 20 02
        ld      a,"."                                          ;#75BB: 3E 2E
DM_ASCII_CELL_EMIT:
        ; CHPUT the ASCII char + backspace cursor for next cell
        call    BIOS_CHPUT                                     ;#75BD: CD A2 00
        ld      a,8                                            ;#75C0: 3E 08
        jp      BIOS_CHPUT                                     ;#75C2: C3 A2 00

DM_FETCH_AT_ROW_COL:
        ; Compute HL = (FA30) + E*8 + D, call DM_FETCH_BYTE; A = byte at row/col
        ld      bc,(MEGA_HEADER_TYPE)                          ;#75C5: ED 4B 30 FA
        ld      l,e                                            ;#75C9: 6B
        ld      h,0                                            ;#75CA: 26 00
        ld      e,d                                            ;#75CC: 5A
        ld      d,h                                            ;#75CD: 54
        add     hl,hl                                          ;#75CE: 29
        add     hl,hl                                          ;#75CF: 29
        add     hl,hl                                          ;#75D0: 29
        add     hl,de                                          ;#75D1: 19
        add     hl,bc                                          ;#75D2: 09
        call    DM_FETCH_BYTE                                  ;#75D3: CD 7A 76
        ret                                                    ;#75D6: C9

DM_DRAW_FULL_PAGE:
        ; Draw the DM/ZAP page: 16 rows × (addr + 8 hex + 8 ASCII) starting at row 1
        ld      hl,101h                                        ;#75D7: 21 01 01
        call    BIOS_POSIT                                     ;#75DA: CD C6 00
        ld      de,0                                           ;#75DD: 11 00 00
        call    DM_FETCH_AT_ROW_COL                            ;#75E0: CD C5 75
        ld      b,10h                                          ;#75E3: 06 10
DM_DRAW_PAGE_ROW_LOOP:
        ; Outer 16-row hex+ASCII page draw loop
        push    bc                                             ;#75E5: C5
        call    PRINT_HEX_HL                                   ;#75E6: CD 9E 50
        push    hl                                             ;#75E9: E5
        ld      b,8                                            ;#75EA: 06 08
DM_DRAW_PAGE_HEX_LOOP:
        ; Inner 8x space+PRINT_HEX_A byte print loop
        ld      a," "                                          ;#75EC: 3E 20
        call    BIOS_CHPUT                                     ;#75EE: CD A2 00
        call    DM_FETCH_BYTE                                  ;#75F1: CD 7A 76
        call    PRINT_HEX_A                                    ;#75F4: CD A3 50
        inc     hl                                             ;#75F7: 23
        djnz    DM_DRAW_PAGE_HEX_LOOP                          ;#75F8: 10 F2
        pop     hl                                             ;#75FA: E1
        ld      a," "                                          ;#75FB: 3E 20
        call    BIOS_CHPUT                                     ;#75FD: CD A2 00
        call    BIOS_CHPUT                                     ;#7600: CD A2 00
        ld      b,8                                            ;#7603: 06 08
DM_DRAW_PAGE_ASCII_LOOP:
        ; Inner 8x ASCII fetch+out (98h) byte loop
        call    DM_FETCH_BYTE                                  ;#7605: CD 7A 76
        cp      " "                                            ;#7608: FE 20
        jr      nc,DM_PAGE_ASCII_TEST_DEL                      ;#760A: 30 02
        ld      a,"."                                          ;#760C: 3E 2E
DM_PAGE_ASCII_TEST_DEL:
        ; Full-page ASCII: 7Fh → '.'
        cp      7Fh                                            ;#760E: FE 7F
        jr      nz,DM_PAGE_ASCII_TEST_FF                       ;#7610: 20 02
        ld      a,"."                                          ;#7612: 3E 2E
DM_PAGE_ASCII_TEST_FF:
        ; Full-page ASCII: 0FFh → '.'
        cp      0FFh                                           ;#7614: FE FF
        jr      nz,DM_PAGE_ASCII_OUT                           ;#7616: 20 02
        ld      a,"."                                          ;#7618: 3E 2E
DM_PAGE_ASCII_OUT:
        ; Full-page ASCII: raw OUT (98h),a to VDP
        out     (98h),a                                        ;#761A: D3 98
        inc     hl                                             ;#761C: 23
        djnz    DM_DRAW_PAGE_ASCII_LOOP                        ;#761D: 10 E6
        call    PRINT_CR                                       ;#761F: CD B4 42
        pop     bc                                             ;#7622: C1
        djnz    DM_DRAW_PAGE_ROW_LOOP                          ;#7623: 10 C0
        ret                                                    ;#7625: C9

EDITOR_DISPLAY_ADDR:
        ; Position (10,18); fetch byte at (FA32), print as hex; show data preview per mode
        ld      hl,0A12h                                       ;#7626: 21 12 0A
        call    BIOS_POSIT                                     ;#7629: CD C6 00
        ld      de,(MEGA_SCRATCH_W2)                           ;#762C: ED 5B 32 FA
        call    DM_FETCH_AT_ROW_COL                            ;#7630: CD C5 75
        call    PRINT_HEX_HL                                   ;#7633: CD 9E 50
        ld      a,(MEGA_EDITOR_MODE_FLAGS)                     ;#7636: 3A 36 FA
        or      a                                              ;#7639: B7
        ld      hl,(MEGA_SCRATCH_W2)                           ;#763A: 2A 32 FA
        jr      z,EDITOR_DISPLAY_ADDR_HEX                      ;#763D: 28 08
        push    hl                                             ;#763F: E5
        call    DM_DRAW_ASCII_CELL                             ;#7640: CD 9D 75
        pop     hl                                             ;#7643: E1
        jp      DM_DRAW_HEX_CELL                               ;#7644: C3 83 75

EDITOR_DISPLAY_ADDR_HEX:
        ; Mode 0 branch — draw hex cell then ASCII cell
        push    hl                                             ;#7647: E5
        call    DM_DRAW_HEX_CELL                               ;#7648: CD 83 75
        pop     hl                                             ;#764B: E1
        jp      DM_DRAW_ASCII_CELL                             ;#764C: C3 9D 75

DISK_PHYDIO_READ:
        ; Disk PHYDIO read: BC=1F9h, DE=W3, HL=BIOS_DIRBUF; → DISK_REPORT_SECTOR
        ld      bc,1F9h                                        ;#764F: 01 F9 01
        ld      de,(MEGA_SCRATCH_W3)                           ;#7652: ED 5B 34 FA
        ld      hl,(BIOS_DIRBUF)                               ;#7656: 2A 51 F3
        xor     a                                              ;#7659: AF
        call    BIOS_PHYDIO                                    ;#765A: CD 44 01
        jr      DISK_REPORT_SECTOR                             ;#765D: 18 0F

DISK_PHYDIO_WRITE:
        ; Disk PHYDIO write: BC=1F9h (drive 1, 7 sectors), DE=W3, HL=BIOS_DIRBUF
        ld      bc,1F9h                                        ;#765F: 01 F9 01
        ld      de,(MEGA_SCRATCH_W3)                           ;#7662: ED 5B 34 FA
        ld      hl,(BIOS_DIRBUF)                               ;#7666: 2A 51 F3
        xor     a                                              ;#7669: AF
        scf                                                    ;#766A: 37
        call    BIOS_PHYDIO                                    ;#766B: CD 44 01
DISK_REPORT_SECTOR:
        ; Position cursor at (16,12), print current sector number from MEGA_SCRATCH_W3
        ld      hl,1612h                                       ;#766E: 21 12 16
        call    BIOS_POSIT                                     ;#7671: CD C6 00
        ld      hl,(MEGA_SCRATCH_W3)                           ;#7674: 2A 34 FA
        jp      PRINT_HEX_HL                                   ;#7677: C3 9E 50

DM_FETCH_BYTE:
        ; Read byte at HL (slot-aware in ZAP; DIRBUF-base in DM); add (FA38) to A
        call    CHECK_DM_ZAP_MODE                              ;#767A: CD B2 76
        jp      z,DM_FETCH_BYTE_ZAP                            ;#767D: CA 8C 76
        push    hl                                             ;#7680: E5
        push    de                                             ;#7681: D5
        ld      de,(BIOS_DIRBUF)                               ;#7682: ED 5B 51 F3
        add     hl,de                                          ;#7686: 19
        ld      a,(hl)                                         ;#7687: 7E
        pop     de                                             ;#7688: D1
        pop     hl                                             ;#7689: E1
        jr      DM_FETCH_BYTE_OFFSET                           ;#768A: 18 03

DM_FETCH_BYTE_ZAP:
        ; ZAP-mode read via MEGA_SLOT_READ_HL path
        call    MEGA_SLOT_READ_HL                              ;#768C: CD 16 FA
DM_FETCH_BYTE_OFFSET:
        ; Common tail — push HL, add DM_OFFSET, pop, ret
        push    hl                                             ;#768F: E5
        ld      hl,MEGA_DM_OFFSET                              ;#7690: 21 38 FA
        add     a,(hl)                                         ;#7693: 86
        pop     hl                                             ;#7694: E1
        ret                                                    ;#7695: C9

DM_WRITE_BYTE:
        ; Write byte A at HL — subtracts DM_OFFSET from A first; dispatches DM vs ZAP
        push    de                                             ;#7696: D5
        push    af                                             ;#7697: F5
        ld      a,(MEGA_DM_OFFSET)                             ;#7698: 3A 38 FA
        ld      e,a                                            ;#769B: 5F
        pop     af                                             ;#769C: F1
        sub     e                                              ;#769D: 93
        ld      e,a                                            ;#769E: 5F
        call    CHECK_DM_ZAP_MODE                              ;#769F: CD B2 76
        ld      a,e                                            ;#76A2: 7B
        pop     de                                             ;#76A3: D1
        jp      z,MEGA_SLOT_WRITE                              ;#76A4: CA 10 FA
        push    de                                             ;#76A7: D5
        push    hl                                             ;#76A8: E5
        ld      de,(BIOS_DIRBUF)                               ;#76A9: ED 5B 51 F3
        add     hl,de                                          ;#76AD: 19
        ld      (hl),a                                         ;#76AE: 77
        pop     hl                                             ;#76AF: E1
        pop     de                                             ;#76B0: D1
        ret                                                    ;#76B1: C9

CHECK_DM_ZAP_MODE:
        ; Tiny helper — load DM_ZAP_MODE (FA37), set flags (Z = display, NZ = zap)
        ld      a,(DM_ZAP_MODE)                                ;#76B2: 3A 37 FA
        or      a                                              ;#76B5: B7
        ret                                                    ;#76B6: C9

EDITOR_PROMPT_SAVE:
        ; Show "Gravar? (RETURN=Sim):" at row 1 col 20, read key; on RETURN call save
        call    BIOS_BEEP                                      ;#76B7: CD 13 11
        ld      hl,114h                                        ;#76BA: 21 14 01
        call    BIOS_POSIT                                     ;#76BD: CD C6 00
        call    PRINT_INLINE_STRING                            ;#76C0: CD 8A 50
        db      "Gravar? (RETURN=Sim):"C                       ;#76C3: 47 72 61 76 61 72 3F 20 28 52 45 54 55 52 4E 3D 53 69 6D 29 BA
        call    BIOS_CHGET                                     ;#76D8: CD 9F 00
        cp      "\r"                                           ;#76DB: FE 0D
        call    z,DISK_PHYDIO_WRITE                            ;#76DD: CC 5F 76
        ld      hl,114h                                        ;#76E0: 21 14 01
        call    BIOS_POSIT                                     ;#76E3: CD C6 00
        ld      b,1Fh                                          ;#76E6: 06 1F
        ld      a," "                                          ;#76E8: 3E 20

EDITOR_PROMPT_SAVE_CLEAR_LOOP:
        ; 1Fh space rst 18h clear of save-prompt row
        rst     18h                                            ;#76EA: DF
        djnz    EDITOR_PROMPT_SAVE_CLEAR_LOOP                  ;#76EB: 10 FD
        ret                                                    ;#76ED: C9

MEGA_PCMD_SH:
        ; Prompt command "SH" — show (file info, status)
        call    SKIP_SPACES                                    ;#76EE: CD F3 43
        jr      z,MEGA_PCMD_SH_SYNTAX_ERR                      ;#76F1: 28 4F
        cp      ","                                            ;#76F3: FE 2C
        ld      de,(MEGA_HEADER_TYPE)                          ;#76F5: ED 5B 30 FA
        inc     de                                             ;#76F9: 13
        jr      z,MEGA_PCMD_SH_STORE_BASE                      ;#76FA: 28 03
        call    PARSE_HEX_WORD                                 ;#76FC: CD BA 50
MEGA_PCMD_SH_STORE_BASE:
        ; Store parsed/default base to MEGA_HEADER_TYPE
        ld      (MEGA_HEADER_TYPE),de                          ;#76FF: ED 53 30 FA
        ld      a,(hl)                                         ;#7703: 7E
        cp      ","                                            ;#7704: FE 2C
        jr      nz,MEGA_PCMD_SH_SYNTAX_ERR                     ;#7706: 20 3A
        inc     hl                                             ;#7708: 23
        ld      iy,MEGA_SCRATCH_W2                             ;#7709: FD 21 32 FA
        call    SKIP_SPACES                                    ;#770D: CD F3 43
        cp      "'"                                            ;#7710: FE 27
        jr      z,MEGA_PCMD_SH_STRING_ARG                      ;#7712: 28 31
MEGA_PCMD_SH_NEXT_ENTRY:
        ; Per-entry loop top — SKIP_SPACES then dispatch number / wildcard / `'` string
        call    SKIP_SPACES                                    ;#7714: CD F3 43
        jr      z,MEGA_PCMD_SH_WILDCARD                        ;#7717: 28 23
        cp      ","                                            ;#7719: FE 2C
        jr      z,MEGA_PCMD_SH_WILDCARD                        ;#771B: 28 1F
        call    PARSE_HEX_WORD                                 ;#771D: CD BA 50
        jr      c,MEGA_PCMD_SH_SYNTAX_ERR                      ;#7720: 38 20
        inc     d                                              ;#7722: 14
        dec     d                                              ;#7723: 15
        jr      nz,MEGA_PCMD_SH_SYNTAX_ERR                     ;#7724: 20 1C
        ld      (iy),e                                         ;#7726: FD 73 00
        ld      (iy+1),0                                       ;#7729: FD 36 01 00
MEGA_PCMD_SH_ADVANCE_SLOT:
        ; Advance iy by 2 slots (after numeric or wildcard entry)
        inc     iy                                             ;#772D: FD 23
        inc     iy                                             ;#772F: FD 23
        ld      a,(hl)                                         ;#7731: 7E
        inc     hl                                             ;#7732: 23
        or      a                                              ;#7733: B7
        jr      nz,MEGA_PCMD_SH_NEXT_ENTRY                     ;#7734: 20 DE
MEGA_PCMD_SH_LIST_END:
        ; Source exhausted → mark previous slot's flag as FFh (terminator), jr to _SEARCH
        ld      (iy-1),0FFh                                    ;#7736: FD 36 FF FF
        jr      MEGA_PCMD_SH_SEARCH                            ;#773A: 18 33

MEGA_PCMD_SH_WILDCARD:
        ; Empty arg → mark current MEGA_SCRATCH_W2 slot's flag byte as 1 (match-any)
        ld      (iy+1),1                                       ;#773C: FD 36 01 01
        jr      MEGA_PCMD_SH_ADVANCE_SLOT                      ;#7740: 18 EB

MEGA_PCMD_SH_SYNTAX_ERR:
        ; jr-reachable trampoline to SYNTAX_ERROR_LF (reached from 6 PARSE/SKIP checks)
        jp      SYNTAX_ERROR_LF                                ;#7742: C3 47 43

MEGA_PCMD_SH_STRING_ARG:
        ; `'..'` arg: store first char then per-char (curr-prev) diffs at iy, jp 77A7
        inc     hl                                             ;#7745: 23
        ld      a,(hl)                                         ;#7746: 7E
        or      a                                              ;#7747: B7
        jr      z,MEGA_PCMD_SH_SYNTAX_ERR                      ;#7748: 28 F8
        cp      3                                              ;#774A: FE 03
        ret     z                                              ;#774C: C8
        ld      (iy),a                                         ;#774D: FD 77 00
        inc     iy                                             ;#7750: FD 23
        ld      c,a                                            ;#7752: 4F
        inc     hl                                             ;#7753: 23
        ld      a,(hl)                                         ;#7754: 7E
        or      a                                              ;#7755: B7
        jr      z,MEGA_PCMD_SH_SYNTAX_ERR                      ;#7756: 28 EA
        ld      e,0                                            ;#7758: 1E 00
MEGA_PCMD_SH_STR_DIFF_LOOP:
        ; Per-char diff loop top — STRING_LIT_END_CHECK_MS
        call    STRING_LIT_END_CHECK_MS                        ;#775A: CD 3F 78
        inc     hl                                             ;#775D: 23
        jr      c,MEGA_PCMD_SH_SEARCH_STR                      ;#775E: 38 47
        or      a                                              ;#7760: B7
        jr      z,MEGA_PCMD_SH_SEARCH_STR                      ;#7761: 28 44
        push    af                                             ;#7763: F5
        sub     c                                              ;#7764: 91
        ld      (iy),a                                         ;#7765: FD 77 00
        inc     iy                                             ;#7768: FD 23
        pop     af                                             ;#776A: F1
        ld      c,a                                            ;#776B: 4F
        inc     e                                              ;#776C: 1C
        jr      MEGA_PCMD_SH_STR_DIFF_LOOP                     ;#776D: 18 EB

MEGA_PCMD_SH_SEARCH:
        ; After list parse: walk cart from MEGA_HEADER_TYPE looking for the byte run
        ld      hl,(MEGA_HEADER_TYPE)                          ;#776F: 2A 30 FA
MEGA_PCMD_SH_BYTE_SEARCH:
        ; Byte-search loop top — push hl, load (iy+1) flag
        push    hl                                             ;#7772: E5
        ld      iy,MEGA_SCRATCH_W2                             ;#7773: FD 21 32 FA
MEGA_PCMD_SH_CMP_BYTE:
        ; Compare cart byte to pattern slot (iy)
        ld      a,(iy+1)                                       ;#7777: FD 7E 01
        cp      1                                              ;#777A: FE 01
        jr      z,MEGA_PCMD_SH_MATCH_ENTRY                     ;#777C: 28 0F
        call    MEGA_SLOT_READ_HL                              ;#777E: CD 16 FA
        cp      (iy)                                           ;#7781: FD BE 00
        jr      z,MEGA_PCMD_SH_MATCH_ENTRY                     ;#7784: 28 07
        pop     hl                                             ;#7786: E1
        inc     hl                                             ;#7787: 23
        ld      a,h                                            ;#7788: 7C
        or      l                                              ;#7789: B5
        jr      nz,MEGA_PCMD_SH_BYTE_SEARCH                    ;#778A: 20 E6
        ret                                                    ;#778C: C9

MEGA_PCMD_SH_MATCH_ENTRY:
        ; Entry matched/wildcard — advance iy/hl, or PRINT result if (iy+1)=FFh
        ld      a,(iy+1)                                       ;#778D: FD 7E 01
        cp      0FFh                                           ;#7790: FE FF
        jr      z,MEGA_PCMD_SH_PRINT_MATCH                     ;#7792: 28 07
        inc     iy                                             ;#7794: FD 23
        inc     iy                                             ;#7796: FD 23
        inc     hl                                             ;#7798: 23
        jr      MEGA_PCMD_SH_CMP_BYTE                          ;#7799: 18 DC

MEGA_PCMD_SH_PRINT_MATCH:
        ; Match found — pop hl, save HEADER_TYPE, PRINT_HEX_HL+CR
        pop     hl                                             ;#779B: E1
        ld      (MEGA_HEADER_TYPE),hl                          ;#779C: 22 30 FA
        call    PRINT_HEX_HL                                   ;#779F: CD 9E 50
        ld      a,"\r"                                         ;#77A2: 3E 0D
        jp      PRINT_CHAR                                     ;#77A4: C3 B6 42

MEGA_PCMD_SH_SEARCH_STR:
        ; Differential string search — match char-diff pattern, ignore charset offset
        ld      hl,(MEGA_HEADER_TYPE)                          ;#77A7: 2A 30 FA
MEGA_PCMD_SH_STR_OUTER:
        ; Differential string search outer loop top
        push    hl                                             ;#77AA: E5
        call    MEGA_SLOT_READ_HL                              ;#77AB: CD 16 FA
        ld      c,a                                            ;#77AE: 4F
        ld      d,e                                            ;#77AF: 53
        inc     hl                                             ;#77B0: 23
        ld      iy,MEGA_SCRATCH_W2_HI                          ;#77B1: FD 21 33 FA
MEGA_PCMD_SH_STR_INNER:
        ; Differential string search inner — fetch+diff compare
        call    MEGA_SLOT_READ_HL                              ;#77B5: CD 16 FA
        ld      b,a                                            ;#77B8: 47
        sub     c                                              ;#77B9: 91
        cp      (iy)                                           ;#77BA: FD BE 00
        ld      c,b                                            ;#77BD: 48
        jr      z,MEGA_PCMD_SH_STR_ADVANCE                     ;#77BE: 28 07
        pop     hl                                             ;#77C0: E1
        inc     hl                                             ;#77C1: 23
        ld      a,h                                            ;#77C2: 7C
        or      l                                              ;#77C3: B5
        jr      nz,MEGA_PCMD_SH_STR_OUTER                      ;#77C4: 20 E4
        ret                                                    ;#77C6: C9

MEGA_PCMD_SH_STR_ADVANCE:
        ; Advance to next char (inc hl/iy, dec d)
        inc     hl                                             ;#77C7: 23
        inc     iy                                             ;#77C8: FD 23
        dec     d                                              ;#77CA: 15
        jr      nz,MEGA_PCMD_SH_STR_INNER                      ;#77CB: 20 E8
        pop     hl                                             ;#77CD: E1
        ld      (MEGA_HEADER_TYPE),hl                          ;#77CE: 22 30 FA
        call    PRINT_HEX_HL                                   ;#77D1: CD 9E 50
        ld      a," "                                          ;#77D4: 3E 20
        call    BIOS_CHPUT                                     ;#77D6: CD A2 00
        ld      a,(MEGA_SCRATCH_W2)                            ;#77D9: 3A 32 FA
        ld      b,a                                            ;#77DC: 47
        call    MEGA_SLOT_READ_HL                              ;#77DD: CD 16 FA
        sub     b                                              ;#77E0: 90
        cp      80h                                            ;#77E1: FE 80
        ld      b,a                                            ;#77E3: 47
        ld      a,"+"                                          ;#77E4: 3E 2B
        jr      c,MEGA_PCMD_SH_PRINT_DIFF                      ;#77E6: 38 06
        ld      a,b                                            ;#77E8: 78
        neg                                                    ;#77E9: ED 44
        ld      b,a                                            ;#77EB: 47
        ld      a,"-"                                          ;#77EC: 3E 2D
MEGA_PCMD_SH_PRINT_DIFF:
        ; Emit signed +/- sign char then |offset| hex + CR
        call    BIOS_CHPUT                                     ;#77EE: CD A2 00
        ld      a,b                                            ;#77F1: 78
        call    PRINT_HEX_A                                    ;#77F2: CD A3 50
        ld      a,"\r"                                         ;#77F5: 3E 0D
        jp      PRINT_CHAR                                     ;#77F7: C3 B6 42

MEGA_PCMD_MS:
        ; Prompt command "MS" — memory save / move (disk)
        call    SKIP_SPACES                                    ;#77FA: CD F3 43
        jp      z,SYNTAX_ERROR_LF                              ;#77FD: CA 47 43
        call    PARSE_HEX_WORD                                 ;#7800: CD BA 50
        ld      a,(hl)                                         ;#7803: 7E
        cp      ","                                            ;#7804: FE 2C
        jp      nz,SYNTAX_ERROR_LF                             ;#7806: C2 47 43
        inc     hl                                             ;#7809: 23
        ld      a,(hl)                                         ;#780A: 7E
        cp      "-"                                            ;#780B: FE 2D
        ld      a,0                                            ;#780D: 3E 00
        jr      nz,MS_PARSE_SRC_OFFSET                         ;#780F: 20 02
        inc     a                                              ;#7811: 3C
        inc     hl                                             ;#7812: 23
MS_PARSE_SRC_OFFSET:
        ; MS: sign byte handled — push DE, parse hex source offset word
        push    de                                             ;#7813: D5
        push    af                                             ;#7814: F5
        call    PARSE_REQUIRED_HEX_WORD                        ;#7815: CD AD 6C
        pop     af                                             ;#7818: F1
        or      a                                              ;#7819: B7
        jr      z,MS_APPLY_OFFSET                              ;#781A: 28 04
        ld      a,e                                            ;#781C: 7B
        neg                                                    ;#781D: ED 44
        ld      e,a                                            ;#781F: 5F
MS_APPLY_OFFSET:
        ; MS: signed offset finalized in E — copy to C and check comma
        ld      c,e                                            ;#7820: 4B
        ld      a,(hl)                                         ;#7821: 7E
        cp      ","                                            ;#7822: FE 2C
        pop     de                                             ;#7824: D1
        jp      nz,SYNTAX_ERROR_LF                             ;#7825: C2 47 43
        inc     hl                                             ;#7828: 23
        ld      a,(hl)                                         ;#7829: 7E
        cp      "'"                                            ;#782A: FE 27
        jp      nz,SYNTAX_ERROR_LF                             ;#782C: C2 47 43
MS_WRITE_LOOP:
        ; MS: per-char body — fetch from src string, add offset, SLOT_WRITE to dest
        inc     hl                                             ;#782F: 23
        call    STRING_LIT_END_CHECK_MS                        ;#7830: CD 3F 78
        ret     c                                              ;#7833: D8
        or      a                                              ;#7834: B7
        ret     z                                              ;#7835: C8
        add     a,c                                            ;#7836: 81
        ex      de,hl                                          ;#7837: EB
        call    MEGA_SLOT_WRITE                                ;#7838: CD 10 FA
        ex      de,hl                                          ;#783B: EB
        inc     de                                             ;#783C: 13
        jr      MS_WRITE_LOOP                                  ;#783D: 18 F0

STRING_LIT_END_CHECK_MS:
        ; Duplicate of STRING_LIT_END_CHECK located inside MEGA_PCMD_MS string parser
        ld      a,(hl)                                         ;#783F: 7E
        cp      "'"                                            ;#7840: FE 27
        jr      nz,STRING_LIT_MS_CHAR_OK                       ;#7842: 20 06
        inc     hl                                             ;#7844: 23
        ld      a,(hl)                                         ;#7845: 7E
        cp      "'"                                            ;#7846: FE 27
        jr      nz,STRING_LIT_MS_END                           ;#7848: 20 02
STRING_LIT_MS_CHAR_OK:
        ; Not a quote — return Z (continue copy)
        and     a                                              ;#784A: A7
        ret                                                    ;#784B: C9

STRING_LIT_MS_END:
        ; `''` or terminator — return C (end)
        scf                                                    ;#784C: 37
        ret                                                    ;#784D: C9

MEGA_CMD_RENEW:
        ; `CALL RENEW` — walk BASIC tokens, then reset VARTAB/ARYTAB/STREND
        ld      hl,(BIOS_TXTTAB)                               ;#784E: 2A 76 F6
        push    hl                                             ;#7851: E5
        dec     hl                                             ;#7852: 2B
        ld      (hl),0                                         ;#7853: 36 00
        ld      de,5                                           ;#7855: 11 05 00
        add     hl,de                                          ;#7858: 19
RENEW_TOKEN_LOOP:
        ; Body of MEGA_CMD_RENEW — skips token-encoded operands while scanning to EOF
        ld      a,(hl)                                         ;#7859: 7E
        inc     hl                                             ;#785A: 23
        or      a                                              ;#785B: B7
        jr      z,RENEW_FINALIZE                               ;#785C: 28 2A
        cp      0Fh                                            ;#785E: FE 0F
        jr      nc,RENEW_TOKEN_TEST_LIT                        ;#7860: 30 04
RENEW_SKIP_TWO:
        ; 1Ch numeric-literal token — skip 2 bytes then loop
        inc     hl                                             ;#7862: 23
        inc     hl                                             ;#7863: 23
        jr      RENEW_TOKEN_LOOP                               ;#7864: 18 F3

RENEW_TOKEN_TEST_LIT:
        ; A>=0Fh arm — test for 0Fh (1-byte literal) → skip 1 byte
        cp      0Fh                                            ;#7866: FE 0F
        jr      nz,RENEW_TOKEN_TEST_NUM                        ;#7868: 20 03
        inc     hl                                             ;#786A: 23
        jr      RENEW_TOKEN_LOOP                               ;#786B: 18 EC

RENEW_TOKEN_TEST_NUM:
        ; A!=0Fh — test for 1Bh/1Ch/1Dh numeric-literal token classes
        cp      1Bh                                            ;#786D: FE 1B
        jr      c,RENEW_TOKEN_LOOP                             ;#786F: 38 E8
        cp      1Ch                                            ;#7871: FE 1C
        jr      z,RENEW_SKIP_TWO                               ;#7873: 28 ED
        cp      1Dh                                            ;#7875: FE 1D
        jr      nz,RENEW_TOKEN_TEST_DBL                        ;#7877: 20 06
        ld      de,4                                           ;#7879: 11 04 00
RENEW_SKIP_ADD:
        ; Shared `add hl,de` + loop — used by both 1Dh (skip 4) and 1Fh (skip 8) arms
        add     hl,de                                          ;#787C: 19
        jr      RENEW_TOKEN_LOOP                               ;#787D: 18 DA

RENEW_TOKEN_TEST_DBL:
        ; A!=1Dh — test for 1Fh double-precision token → skip 8 bytes
        cp      1Fh                                            ;#787F: FE 1F
        jr      nz,RENEW_TOKEN_LOOP                            ;#7881: 20 D6
        ld      de,8                                           ;#7883: 11 08 00
        jr      RENEW_SKIP_ADD                                 ;#7886: 18 F4

RENEW_FINALIZE:
        ; End-of-text reached — sets VARTAB = ARYTAB = STREND = (HL+1) to clear variables
        pop     de                                             ;#7888: D1
        ex      de,hl                                          ;#7889: EB
        ld      (hl),e                                         ;#788A: 73
        inc     hl                                             ;#788B: 23
        ld      (hl),d                                         ;#788C: 72
RENEW_CLEAR_LINKS_LOOP:
        ; Walk line-link chain writing terminator zeros
        ex      de,hl                                          ;#788D: EB
        ld      e,(hl)                                         ;#788E: 5E
        inc     hl                                             ;#788F: 23
        ld      d,(hl)                                         ;#7890: 56
        ld      a,d                                            ;#7891: 7A
        or      e                                              ;#7892: B3
        jr      nz,RENEW_CLEAR_LINKS_LOOP                      ;#7893: 20 F8
        inc     hl                                             ;#7895: 23
        ld      (BIOS_VARTAB),hl                               ;#7896: 22 C2 F6
        ld      (BIOS_ARYTAB),hl                               ;#7899: 22 C4 F6
        ld      (BIOS_STREND),hl                               ;#789C: 22 C6 F6
        pop     hl                                             ;#789F: E1
        and     a                                              ;#78A0: A7
        ret                                                    ;#78A1: C9

MEGA_CMD_BVERIFY:
        ; `CALL BVERIFY` handler — binary verify (cassette/file)
        call    BVERIFY_READ_HEADER                            ;#78A2: CD CB 78
        jr      c,BVERIFY_TAPE_ERROR                           ;#78A5: 38 73
        call    BIOS_TAPION                                    ;#78A7: CD E1 00
        jr      c,BVERIFY_TAPE_ERROR                           ;#78AA: 38 6E
        call    TAPE_READ_WORD_BV                              ;#78AC: CD 0B 79
        push    hl                                             ;#78AF: E5
        call    TAPE_READ_WORD_BV                              ;#78B0: CD 0B 79
        push    hl                                             ;#78B3: E5
        call    TAPE_READ_WORD_BV                              ;#78B4: CD 0B 79
        pop     de                                             ;#78B7: D1
        pop     hl                                             ;#78B8: E1
        inc     de                                             ;#78B9: 13
BVERIFY_COMPARE_LOOP:
        ; Read next tape byte (via exx) and compare with (HL)
        exx                                                    ;#78BA: D9
        call    BIOS_TAPIN                                     ;#78BB: CD E4 00
        exx                                                    ;#78BE: D9
        jr      c,BVERIFY_TAPE_ERROR                           ;#78BF: 38 59
        cp      (hl)                                           ;#78C1: BE
        jp      nz,BVERIFY_MISMATCH                            ;#78C2: C2 16 79
        inc     hl                                             ;#78C5: 23
        rst     20h                                            ;#78C6: E7
        jr      nz,BVERIFY_COMPARE_LOOP                        ;#78C7: 20 F1
        jr      BVERIFY_TAPE_CLEANUP                           ;#78C9: 18 5B

BVERIFY_READ_HEADER:
        ; Read 10 sync-D0h bytes + 6 filename bytes into BIOS_FILNM2; on no-match loop
        call    BIOS_TAPION                                    ;#78CB: CD E1 00
        ret     c                                              ;#78CE: D8
        ld      b,0Ah                                          ;#78CF: 06 0A
BVERIFY_SYNC_LOOP:
        ; 10x TAPIN sync-byte (D0h) verify loop
        push    bc                                             ;#78D1: C5
        call    BIOS_TAPIN                                     ;#78D2: CD E4 00
        pop     bc                                             ;#78D5: C1
        ret     c                                              ;#78D6: D8
        cp      0D0h                                           ;#78D7: FE D0
        jr      nz,BVERIFY_READ_HEADER                         ;#78D9: 20 F0
        djnz    BVERIFY_SYNC_LOOP                              ;#78DB: 10 F4
        ld      hl,BIOS_FILNM2                                 ;#78DD: 21 71 F8
        ld      b,6                                            ;#78E0: 06 06
BVERIFY_FILNAM_LOOP:
        ; 6x TAPIN read filename into BIOS_FILNM2
        exx                                                    ;#78E2: D9
        call    BIOS_TAPIN                                     ;#78E3: CD E4 00
        exx                                                    ;#78E6: D9
        ret     c                                              ;#78E7: D8
        ld      (hl),a                                         ;#78E8: 77
        inc     hl                                             ;#78E9: 23
        djnz    BVERIFY_FILNAM_LOOP                            ;#78EA: 10 F6
        ld      hl,(BIOS_CURLIN)                               ;#78EC: 2A 1C F4
        inc     hl                                             ;#78EF: 23
        ld      a,h                                            ;#78F0: 7C
        or      l                                              ;#78F1: B5
        and     a                                              ;#78F2: A7
        ret     nz                                             ;#78F3: C0
        call    PRINT_INLINE_STRING                            ;#78F4: CD 8A 50
        db      "Achei:"C                                      ;#78F7: 41 63 68 65 69 BA
        ld      hl,BIOS_FILNM2                                 ;#78FD: 21 71 F8
        ld      b,6                                            ;#7900: 06 06

BVERIFY_PRINT_FILNAM_LOOP:
        ; 6x rst 18h print of "Achei:" filename
        ld      a,(hl)                                         ;#7902: 7E
        inc     hl                                             ;#7903: 23
        call    BIOS_CHPUT                                     ;#7904: CD A2 00
        djnz    BVERIFY_PRINT_FILNAM_LOOP                      ;#7907: 10 F9
        and     a                                              ;#7909: A7
        ret                                                    ;#790A: C9

TAPE_READ_WORD_BV:
        ; Read HL from cassette (low first); duplicate of TAPE_READ_WORD_HL inside BVERIFY
        call    BIOS_TAPIN                                     ;#790B: CD E4 00
        push    af                                             ;#790E: F5
        call    BIOS_TAPIN                                     ;#790F: CD E4 00
        ld      h,a                                            ;#7912: 67
        pop     af                                             ;#7913: F1
        ld      l,a                                            ;#7914: 6F
        ret                                                    ;#7915: C9

BVERIFY_MISMATCH:
        ; e=14h ("Verify error", MSX err #20) — tape byte didn't match memory
        ld      e,14h                                          ;#7916: 1E 14
        jr      BVERIFY_TAPE_ERROR_BODY                        ;#7918: 18 02

BVERIFY_TAPE_ERROR:
        ; e=13h ("Device I/O error", MSX err #19) — TAPION/TAPIN/header failed
        ld      e,13h                                          ;#791A: 1E 13
BVERIFY_TAPE_ERROR_BODY:
        ; Shared TAPIOF + CALBAS-raise body — joined by _MISMATCH and _TAPE_ERROR
        call    BIOS_TAPIOF                                    ;#791C: CD E7 00
        ld      ix,BIOS_BASIC_ERROR_HANDLER                    ;#791F: DD 21 6F 40
        call    BIOS_CALBAS                                    ;#7923: CD 59 01
BVERIFY_TAPE_CLEANUP:
        ; Post-raise TAPIOF cleanup — ensure motor is off after error returns
        call    BIOS_TAPIOF                                    ;#7926: CD E7 00
        pop     hl                                             ;#7929: E1
        and     a                                              ;#792A: A7
        ret                                                    ;#792B: C9

MEGA_CMD_HEADER:
        ; `CALL HEADER` handler — read a BSAVE tape header and print it
        ; `CALL HEADER` reads a BSAVE-style cassette header and prints its fields:
        ; 1. `TAPION` (00E1h) primes the cassette read; on error → MEGA_HEADER_TAPE_ERROR.
        ; 2. Read 9 sync bytes via `TAPIN` (00E4h) and verify they are identical.
        ; The first sync byte is saved at FA30h as the file-type marker
        ; (`ID_HEADER_BINARY` D0h, `ID_HEADER_BASIC` D3h, `ID_HEADER_ASCII` EAh).
        ; 3. Read 6 filename bytes into BIOS_FILNAM (F866h), print "Programa:<name>".
        ; 4. Dispatch on the type marker to print "Binario", "Basic", "ASCII", or
        ; (fallback) "Ilegal".
        ; 5. For binary headers only, prime `TAPION` again and read 6 more bytes —
        ; three little-endian words — back into FILNAM (F866-F86B), then print
        ; "Inicio :<start>", "Final  :<end>", "Exec.  :<exec>". On any tape
        ; error the routine drops into MEGA_HEADER_TAPE_ERROR.
        call    BIOS_TAPION                                    ;#792C: CD E1 00
        jr      nc,MEGA_HEADER_READ_DATA                       ;#792F: 30 12
MEGA_HEADER_TAPE_ERROR:
        ; Error-cleanup path: TAPOOF and raise BASIC error 13h via CALBAS
        call    BIOS_TAPOOF                                    ;#7931: CD F0 00
        ld      e,13h                                          ;#7934: 1E 13
        ld      ix,BIOS_BASIC_ERROR_HANDLER                    ;#7936: DD 21 6F 40
        call    BIOS_CALBAS                                    ;#793A: CD 59 01
MEGA_HEADER_CLEANUP:
        ; BIOS_TAPOOF, pop saved HL, ret NC — common HEADER exit tail
        call    BIOS_TAPOOF                                    ;#793D: CD F0 00
        pop     hl                                             ;#7940: E1
        and     a                                              ;#7941: A7
        ret                                                    ;#7942: C9

MEGA_HEADER_READ_DATA:
        ; Main body — verify nine sync bytes, read filename, type, addresses
        call    BIOS_TAPIN                                     ;#7943: CD E4 00
        ld      c,a                                            ;#7946: 4F
        ld      b,9                                            ;#7947: 06 09
HEADER_VERIFY_SYNC_LOOP:
        ; Per-byte sync-byte verify: TAPIN, compare to first byte, repeat 9 times
        push    bc                                             ;#7949: C5
        call    BIOS_TAPIN                                     ;#794A: CD E4 00
        pop     bc                                             ;#794D: C1
        jr      c,MEGA_HEADER_TAPE_ERROR                       ;#794E: 38 E1
        cp      c                                              ;#7950: B9
        jr      nz,MEGA_HEADER_TAPE_ERROR                      ;#7951: 20 DE
        djnz    HEADER_VERIFY_SYNC_LOOP                        ;#7953: 10 F4
        ld      (MEGA_HEADER_TYPE),a                           ;#7955: 32 30 FA
        ld      hl,BIOS_FILNAM                                 ;#7958: 21 66 F8
        ld      b,6                                            ;#795B: 06 06
HEADER_READ_FILNAM_LOOP:
        ; Per-byte filename read: TAPIN one byte at a time into BIOS_FILNAM (6 chars)
        push    hl                                             ;#795D: E5
        push    bc                                             ;#795E: C5
        call    BIOS_TAPIN                                     ;#795F: CD E4 00
        pop     bc                                             ;#7962: C1
        pop     hl                                             ;#7963: E1
        jr      c,MEGA_HEADER_TAPE_ERROR                       ;#7964: 38 CB
        ld      (hl),a                                         ;#7966: 77
        inc     hl                                             ;#7967: 23
        djnz    HEADER_READ_FILNAM_LOOP                        ;#7968: 10 F3
        call    PRINT_INLINE_STRING                            ;#796A: CD 8A 50
        db      "Programa:"C                                   ;#796D: 50 72 6F 67 72 61 6D 61 BA
        ld      hl,BIOS_FILNAM                                 ;#7976: 21 66 F8
        ld      b,6                                            ;#7979: 06 06

MEGA_HEADER_PRINT_FILNAM_LOOP:
        ; 6x rst 18h print of "Programa:" filename
        ld      a,(hl)                                         ;#797B: 7E
        rst     18h                                            ;#797C: DF
        inc     hl                                             ;#797D: 23
        djnz    MEGA_HEADER_PRINT_FILNAM_LOOP                  ;#797E: 10 FB
        call    PRINT_CR                                       ;#7980: CD B4 42
        call    PRINT_INLINE_STRING                            ;#7983: CD 8A 50
        db      "Tipo:"C                                       ;#7986: 54 69 70 6F BA
        ld      a,(MEGA_HEADER_TYPE)                           ;#798B: 3A 30 FA
        cp      0D0h                                           ;#798E: FE D0
        jr      z,MEGA_HEADER_PRINT_BIN                        ;#7990: 28 28
        cp      0D3h                                           ;#7992: FE D3
        jr      z,MEGA_HEADER_PRINT_BASIC                      ;#7994: 28 1A
        cp      0EAh                                           ;#7996: FE EA
        jr      z,MEGA_HEADER_PRINT_ASCII                      ;#7998: 28 0C
        call    PRINT_INLINE_STRING                            ;#799A: CD 8A 50
        db      "Ilegal", 87h                                  ;#799D: 49 6C 65 67 61 6C 87
        jr      MEGA_HEADER_CLEANUP                            ;#79A4: 18 97

MEGA_HEADER_PRINT_ASCII:
        ; Type marker EAh path — print "ASCII"
        call    PRINT_INLINE_STRING                            ;#79A6: CD 8A 50
        db      "ASCII"C                                       ;#79A9: 41 53 43 49 C9
        jr      MEGA_HEADER_CLEANUP                            ;#79AE: 18 8D

MEGA_HEADER_PRINT_BASIC:
        ; Type marker D3h path — print "Basic"
        call    PRINT_INLINE_STRING                            ;#79B0: CD 8A 50
        db      "Basic"C                                       ;#79B3: 42 61 73 69 E3
        jr      MEGA_HEADER_CLEANUP                            ;#79B8: 18 83

MEGA_HEADER_PRINT_BIN:
        ; Type marker D0h path — print "Binario" and continue to read addresses
        call    PRINT_INLINE_STRING                            ;#79BA: CD 8A 50
        db      "Binario", 8Dh                                 ;#79BD: 42 69 6E 61 72 69 6F 8D
        call    BIOS_TAPION                                    ;#79C5: CD E1 00
        jp      c,MEGA_HEADER_TAPE_ERROR                       ;#79C8: DA 31 79
        ld      hl,BIOS_FILNAM                                 ;#79CB: 21 66 F8
        ld      b,6                                            ;#79CE: 06 06

MEGA_HEADER_READ_ADDRS_LOOP:
        ; 6x TAPIN read of start/end/exec addresses
        push    hl                                             ;#79D0: E5
        push    bc                                             ;#79D1: C5
        call    BIOS_TAPIN                                     ;#79D2: CD E4 00
        pop     bc                                             ;#79D5: C1
        pop     hl                                             ;#79D6: E1
        jp      c,MEGA_HEADER_TAPE_ERROR                       ;#79D7: DA 31 79
        ld      (hl),a                                         ;#79DA: 77
        inc     hl                                             ;#79DB: 23
        djnz    MEGA_HEADER_READ_ADDRS_LOOP                    ;#79DC: 10 F2
        call    PRINT_INLINE_STRING                            ;#79DE: CD 8A 50
        db      "Inicio :"C                                    ;#79E1: 49 6E 69 63 69 6F 20 BA
        ld      hl,(BIOS_FILNAM)                               ;#79E9: 2A 66 F8
        call    PRINT_HEX_HL                                   ;#79EC: CD 9E 50
        call    PRINT_CR                                       ;#79EF: CD B4 42
        call    PRINT_INLINE_STRING                            ;#79F2: CD 8A 50
        db      "Final  :"C                                    ;#79F5: 46 69 6E 61 6C 20 20 BA
        ld      hl,(BIOS_FILNAM+2)                             ;#79FD: 2A 68 F8
        call    PRINT_HEX_HL                                   ;#7A00: CD 9E 50
        call    PRINT_CR                                       ;#7A03: CD B4 42
        call    PRINT_INLINE_STRING                            ;#7A06: CD 8A 50
        db      "Exec.  :"C                                    ;#7A09: 45 78 65 63 2E 20 20 BA
        ld      hl,(BIOS_FILNAM+4)                             ;#7A11: 2A 6A F8
        call    PRINT_HEX_HL                                   ;#7A14: CD 9E 50
        call    PRINT_CR                                       ;#7A17: CD B4 42
        jp      MEGA_HEADER_CLEANUP                            ;#7A1A: C3 3D 79

MEGA_PCMD_LOAD:
        ; Prompt command "LOAD" — load source/binary file (",B" suffix → binary)
        call    SAVELOAD_PARSE_FILENAME                        ;#7A1D: CD E8 7B
        cp      '"'                                            ;#7A20: FE 22
        jp      z,MERGE_APPEND_ENTRY                           ;#7A22: CA A8 4A
        push    af                                             ;#7A25: F5
        xor     a                                              ;#7A26: AF
        ld      (MEGA_EDITOR_MODE_FLAGS),a                     ;#7A27: 32 36 FA
        call    SKIP_SPACES                                    ;#7A2A: CD F3 43
        jr      z,LOAD_OPEN_DEVICE_CHECK                       ;#7A2D: 28 16
        cp      ","                                            ;#7A2F: FE 2C
        jp      nz,SYNTAX_ERROR_LF                             ;#7A31: C2 47 43
        call    SKIP_SPACES_ADVANCE                            ;#7A34: CD F2 43
        cp      "B"                                            ;#7A37: FE 42
        ld      (MEGA_EDITOR_MODE_FLAGS),a                     ;#7A39: 32 36 FA
        jp      nz,SYNTAX_ERROR_LF                             ;#7A3C: C2 47 43
        call    SKIP_SPACES_ADVANCE                            ;#7A3F: CD F2 43
        jp      nz,SYNTAX_ERROR_LF                             ;#7A42: C2 47 43
LOAD_OPEN_DEVICE_CHECK:
        ; After arg parse: check first char of filename for ":" (cassette path → CAS open)
        pop     af                                             ;#7A45: F1
        cp      ":"                                            ;#7A46: FE 3A
        jp      z,LOAD_FILE_OPEN                               ;#7A48: CA F0 7C
        ld      a,(BIOS_HTIMI)                                 ;#7A4B: 3A 9F FD
        cp      0C9h                                           ;#7A4E: FE C9
        jp      z,LOAD_FILE_OPEN                               ;#7A50: CA F0 7C
        ld      de,MEGA_FILE_BUFFER                            ;#7A53: 11 76 F9
        ld      c,BDOS_SETDTA                                  ;#7A56: 0E 1A
        call    BDOS                                           ;#7A58: CD 7D F3
        ld      de,DM_ZAP_MODE                                 ;#7A5B: 11 37 FA
        ld      c,BDOS_OPEN                                    ;#7A5E: 0E 0F
        call    BDOS                                           ;#7A60: CD 7D F3
        or      a                                              ;#7A63: B7
        ld      a,80h                                          ;#7A64: 3E 80
        ld      (MEGA_FILE_BUF_IDX),a                          ;#7A66: 32 75 F9
        jr      z,LOAD_AFTER_OPEN                              ;#7A69: 28 1A
        call    PRINT_INLINE_STRING                            ;#7A6B: CD 8A 50
        db      "Arquivo inexistente", 8Dh                     ;#7A6E: 41 72 71 75 69 76 6F 20 69 6E 65 78 69 73 74 65 6E 74 65 8D
        jp      SYNTAX_ERROR_LF                                ;#7A82: C3 47 43

LOAD_AFTER_OPEN:
        ; BDOS_OPEN succeeded: read first byte to check FEh BSAVE-magic header marker
        call    FILE_READ_BYTE                                 ;#7A85: CD 9B 7B
        cp      0FEh                                           ;#7A88: FE FE
        jr      z,LOAD_FILE_HEADER                             ;#7A8A: 28 17
PRINT_ACCESS_ERROR:
        ; Print "Acesso incorreto\r" inline string, then jp SYNTAX_ERROR_LF
        call    PRINT_INLINE_STRING                            ;#7A8C: CD 8A 50
        db      "Acesso incorreto", 8Dh                        ;#7A8F: 41 63 65 73 73 6F 20 69 6E 63 6F 72 72 65 74 6F 8D
        jp      SYNTAX_ERROR_LF                                ;#7AA0: C3 47 43

LOAD_FILE_HEADER:
        ; Magic OK: read 2-byte load address into MEGA_HEADER_TYPE, then end address
        call    FILE_READ_BYTE                                 ;#7AA3: CD 9B 7B
        ld      l,a                                            ;#7AA6: 6F
        call    FILE_READ_BYTE                                 ;#7AA7: CD 9B 7B
        ld      h,a                                            ;#7AAA: 67
        ld      (MEGA_HEADER_TYPE),hl                          ;#7AAB: 22 30 FA
        push    hl                                             ;#7AAE: E5
        call    FILE_READ_BYTE                                 ;#7AAF: CD 9B 7B
        ld      l,a                                            ;#7AB2: 6F
        call    FILE_READ_BYTE                                 ;#7AB3: CD 9B 7B
        ld      h,a                                            ;#7AB6: 67
        push    hl                                             ;#7AB7: E5
        ld      (MEGA_SCRATCH_W2),hl                           ;#7AB8: 22 32 FA
        call    FILE_READ_BYTE                                 ;#7ABB: CD 9B 7B
        ld      l,a                                            ;#7ABE: 6F
        call    FILE_READ_BYTE                                 ;#7ABF: CD 9B 7B
        ld      h,a                                            ;#7AC2: 67
        ld      (MEGA_SCRATCH_W3),hl                           ;#7AC3: 22 34 FA
        inc     hl                                             ;#7AC6: 23
        ld      a,h                                            ;#7AC7: 7C
        or      l                                              ;#7AC8: B5
        jr      z,DOS_LOAD_RESET_PASS1                         ;#7AC9: 28 06
        call    EDITOR_MODE_TEST                               ;#7ACB: CD 36 7E
        jp      z,PRINT_ACCESS_ERROR                           ;#7ACE: CA 8C 7A
DOS_LOAD_RESET_PASS1:
        ; DOS LOAD: clear MEGA_PASS1_DONE_FLAG and test editor mode
        xor     a                                              ;#7AD1: AF
        ld      (MEGA_PASS1_DONE_FLAG),a                       ;#7AD2: 32 26 EC
        call    EDITOR_MODE_TEST                               ;#7AD5: CD 36 7E
        jr      nz,DOS_LOAD_RAM_SETUP                          ;#7AD8: 20 0C
        ld      hl,(MEGA_HEADER_TYPE)                          ;#7ADA: 2A 30 FA
        ld      (MEGA_SRC_BUF_START),hl                        ;#7ADD: 22 01 EC
        ld      hl,(MEGA_SCRATCH_W2)                           ;#7AE0: 2A 32 FA
        ld      (MEGA_SRC_BUF_HEAD),hl                         ;#7AE3: 22 03 EC
DOS_LOAD_RAM_SETUP:
        ; DOS LOAD: pop end/start addrs, fall into LOAD_BYTE_TO_RAM_LOOP
        pop     de                                             ;#7AE6: D1
        pop     hl                                             ;#7AE7: E1
LOAD_BYTE_TO_RAM_LOOP:
        ; Read bytes from file via FILE_READ_BYTE, slot-write at HL until HL=DE
        call    FILE_READ_BYTE                                 ;#7AE8: CD 9B 7B
        call    MEGA_SLOT_WRITE                                ;#7AEB: CD 10 FA
        rst     20h                                            ;#7AEE: E7
        ret     z                                              ;#7AEF: C8
        inc     hl                                             ;#7AF0: 23
        jr      LOAD_BYTE_TO_RAM_LOOP                          ;#7AF1: 18 F5

MEGA_PCMD_SAVE:
        ; Prompt command "SAVE" — save source/binary to file
        call    SAVELOAD_PARSE_FILENAME                        ;#7AF3: CD E8 7B
        cp      '"'                                            ;#7AF6: FE 22
        jp      z,MEGA_SAVE_CASSETTE                           ;#7AF8: CA 21 4A
        call    MEGA_SAVE_PARSE_RANGE                          ;#7AFB: CD A9 7D
        cp      ":"                                            ;#7AFE: FE 3A
        jp      z,TAPE_BIN_SAVE_START                          ;#7B00: CA 74 7C
        ld      a,(BIOS_HTIMI)                                 ;#7B03: 3A 9F FD
        cp      0C9h                                           ;#7B06: FE C9
        jp      z,TAPE_BIN_SAVE_START                          ;#7B08: CA 74 7C
        ld      c,BDOS_SETDTA                                  ;#7B0B: 0E 1A
        ld      de,MEGA_FILE_BUFFER                            ;#7B0D: 11 76 F9
        call    BDOS                                           ;#7B10: CD 7D F3
        ld      c,BDOS_FMAKE                                   ;#7B13: 0E 16
        ld      de,DM_ZAP_MODE                                 ;#7B15: 11 37 FA
        call    BDOS                                           ;#7B18: CD 7D F3
        jr      nz,FILE_WRITE_ERROR                            ;#7B1B: 20 51
        xor     a                                              ;#7B1D: AF
        ld      (MEGA_FILE_BUF_IDX),a                          ;#7B1E: 32 75 F9
        ld      a,0FEh                                         ;#7B21: 3E FE
        call    FILE_WRITE_BYTE                                ;#7B23: CD C1 7B
        ld      hl,(MEGA_HEADER_TYPE)                          ;#7B26: 2A 30 FA
        push    hl                                             ;#7B29: E5
        ld      a,l                                            ;#7B2A: 7D
        call    FILE_WRITE_BYTE                                ;#7B2B: CD C1 7B
        ld      a,h                                            ;#7B2E: 7C
        call    FILE_WRITE_BYTE                                ;#7B2F: CD C1 7B
        ld      hl,(MEGA_SCRATCH_W2)                           ;#7B32: 2A 32 FA
        push    hl                                             ;#7B35: E5
        ld      a,l                                            ;#7B36: 7D
        call    FILE_WRITE_BYTE                                ;#7B37: CD C1 7B
        ld      a,h                                            ;#7B3A: 7C
        call    FILE_WRITE_BYTE                                ;#7B3B: CD C1 7B
        ld      hl,(MEGA_SCRATCH_W3)                           ;#7B3E: 2A 34 FA
        ld      a,l                                            ;#7B41: 7D
        call    FILE_WRITE_BYTE                                ;#7B42: CD C1 7B
        ld      a,h                                            ;#7B45: 7C
        call    FILE_WRITE_BYTE                                ;#7B46: CD C1 7B
        pop     hl                                             ;#7B49: E1
        pop     de                                             ;#7B4A: D1
SAVE_DOS_WRITE_LOOP:
        ; Per-byte: MEGA_SLOT_READ_DE then FILE_WRITE_BYTE, advance, loop
        call    MEGA_SLOT_READ_DE                              ;#7B4B: CD 1C FA
        call    FILE_WRITE_BYTE                                ;#7B4E: CD C1 7B
        rst     20h                                            ;#7B51: E7
        inc     de                                             ;#7B52: 13
        jr      nz,SAVE_DOS_WRITE_LOOP                         ;#7B53: 20 F6
        ld      a,(MEGA_FILE_BUF_IDX)                          ;#7B55: 3A 75 F9
        or      a                                              ;#7B58: B7
        jr      z,SAVE_DOS_CLOSE                               ;#7B59: 28 0A
        ld      de,DM_ZAP_MODE                                 ;#7B5B: 11 37 FA
        ld      c,BDOS_WRSEQ                                   ;#7B5E: 0E 15
        call    BDOS                                           ;#7B60: CD 7D F3
        jr      nz,FILE_WRITE_ERROR                            ;#7B63: 20 09

SAVE_DOS_CLOSE:
        ; Tail after all bytes written: BDOS_CLOSE + check, finish the SAVE
        ld      c,BDOS_CLOSE                                   ;#7B65: 0E 10
        ld      de,DM_ZAP_MODE                                 ;#7B67: 11 37 FA
        call    BDOS                                           ;#7B6A: CD 7D F3
        ret     z                                              ;#7B6D: C8
FILE_WRITE_ERROR:
        ; Print "Erro de gravacao\r" then jp SYNTAX_ERROR_LF (DOS write failure)
        call    PRINT_INLINE_STRING                            ;#7B6E: CD 8A 50
        db      "Erro de gravacao", 8Dh                        ;#7B71: 45 72 72 6F 20 64 65 20 67 72 61 76 61 63 61 6F 8D
        jp      SYNTAX_ERROR_LF                                ;#7B82: C3 47 43

FILE_READ_ERROR:
        ; Print "Erro de leitura\r" then jp SYNTAX_ERROR_LF (DOS read failure)
        call    PRINT_INLINE_STRING                            ;#7B85: CD 8A 50
        db      "Erro de leitura", 8Dh                         ;#7B88: 45 72 72 6F 20 64 65 20 6C 65 69 74 75 72 61 8D
        jp      SYNTAX_ERROR_LF                                ;#7B98: C3 47 43

FILE_READ_BYTE:
        ; Read next byte from open file via 128-byte buffer at MEGA_FILE_BUFFER
        push    bc                                             ;#7B9B: C5
        push    de                                             ;#7B9C: D5
        push    hl                                             ;#7B9D: E5
        ld      a,(MEGA_FILE_BUF_IDX)                          ;#7B9E: 3A 75 F9
        cp      80h                                            ;#7BA1: FE 80
        jr      nz,FILE_READ_BYTE_RETURN                       ;#7BA3: 20 0E
        ld      c,BDOS_RDSEQ                                   ;#7BA5: 0E 14
        ld      de,DM_ZAP_MODE                                 ;#7BA7: 11 37 FA
        call    BDOS                                           ;#7BAA: CD 7D F3
        jr      nz,FILE_READ_ERROR                             ;#7BAD: 20 D6
        xor     a                                              ;#7BAF: AF
        ld      (MEGA_FILE_BUF_IDX),a                          ;#7BB0: 32 75 F9
FILE_READ_BYTE_RETURN:
        ; Buffer-byte path: take byte at MEGA_FILE_BUF_IDX, bump idx, ret
        ld      hl,MEGA_FILE_BUF_IDX                           ;#7BB3: 21 75 F9
        ld      e,(hl)                                         ;#7BB6: 5E
        inc     (hl)                                           ;#7BB7: 34
        inc     hl                                             ;#7BB8: 23
        ld      d,0                                            ;#7BB9: 16 00
        add     hl,de                                          ;#7BBB: 19
        ld      a,(hl)                                         ;#7BBC: 7E
        pop     hl                                             ;#7BBD: E1
        pop     de                                             ;#7BBE: D1
        pop     bc                                             ;#7BBF: C1
        ret                                                    ;#7BC0: C9

FILE_WRITE_BYTE:
        ; Write A to open file via the same buffered I/O — flushes when full
        push    hl                                             ;#7BC1: E5
        push    de                                             ;#7BC2: D5
        push    bc                                             ;#7BC3: C5
        push    af                                             ;#7BC4: F5
        ld      hl,MEGA_FILE_BUF_IDX                           ;#7BC5: 21 75 F9
        ld      e,(hl)                                         ;#7BC8: 5E
        ld      d,0                                            ;#7BC9: 16 00
        inc     (hl)                                           ;#7BCB: 34
        inc     hl                                             ;#7BCC: 23
        add     hl,de                                          ;#7BCD: 19
        ld      (hl),a                                         ;#7BCE: 77
        ld      a,e                                            ;#7BCF: 7B
        cp      7Fh                                            ;#7BD0: FE 7F
        jr      nz,FILE_WRITE_BYTE_DONE                        ;#7BD2: 20 0F
        ld      c,BDOS_WRSEQ                                   ;#7BD4: 0E 15
        ld      de,DM_ZAP_MODE                                 ;#7BD6: 11 37 FA
        call    BDOS                                           ;#7BD9: CD 7D F3
        jp      nz,FILE_WRITE_ERROR                            ;#7BDC: C2 6E 7B
        xor     a                                              ;#7BDF: AF
        ld      (MEGA_FILE_BUF_IDX),a                          ;#7BE0: 32 75 F9
FILE_WRITE_BYTE_DONE:
        ; Buffer not full (idx < 7Fh): no flush needed, pop regs and ret
        pop     af                                             ;#7BE3: F1
        pop     bc                                             ;#7BE4: C1
        pop     de                                             ;#7BE5: D1
        pop     hl                                             ;#7BE6: E1
        ret                                                    ;#7BE7: C9

SAVELOAD_PARSE_FILENAME:
        ; Shared routine — parse filename (quoted) and prepare BIOS FCB
        call    SKIP_SPACES                                    ;#7BE8: CD F3 43
        jp      z,SYNTAX_ERROR_LF                              ;#7BEB: CA 47 43
        push    hl                                             ;#7BEE: E5
        ld      b,0Bh                                          ;#7BEF: 06 0B
        ld      hl,DM_ZAP_MODE                                 ;#7BF1: 21 37 FA
        ld      (hl),0                                         ;#7BF4: 36 00
        push    hl                                             ;#7BF6: E5
        inc     hl                                             ;#7BF7: 23
SAVELOAD_FCB_SPACE_FILL_LOOP:
        ; 0Bh space-fill of FCB name area
        ld      (hl)," "                                       ;#7BF8: 36 20
        inc     hl                                             ;#7BFA: 23
        djnz    SAVELOAD_FCB_SPACE_FILL_LOOP                   ;#7BFB: 10 FB
        ld      b,19h                                          ;#7BFD: 06 19
SAVELOAD_FCB_ZERO_FILL_LOOP:
        ; 19h zero-fill of FCB extension/control area
        ld      (hl),0                                         ;#7BFF: 36 00
        inc     hl                                             ;#7C01: 23
        djnz    SAVELOAD_FCB_ZERO_FILL_LOOP                    ;#7C02: 10 FB
        pop     de                                             ;#7C04: D1
        pop     hl                                             ;#7C05: E1
        ld      a,(hl)                                         ;#7C06: 7E
        cp      '"'                                            ;#7C07: FE 22
        ret     z                                              ;#7C09: C8
        push    hl                                             ;#7C0A: E5
        ld      a,(hl)                                         ;#7C0B: 7E
        cp      "C"                                            ;#7C0C: FE 43
        jr      nz,SAVELOAD_FILENAME_NO_PREFIX                 ;#7C0E: 20 17
        inc     hl                                             ;#7C10: 23
        ld      a,(hl)                                         ;#7C11: 7E
        cp      "A"                                            ;#7C12: FE 41
        jr      nz,SAVELOAD_FILENAME_NO_PREFIX                 ;#7C14: 20 11
        inc     hl                                             ;#7C16: 23
        ld      a,(hl)                                         ;#7C17: 7E
        cp      "S"                                            ;#7C18: FE 53
        jr      nz,SAVELOAD_FILENAME_NO_PREFIX                 ;#7C1A: 20 0B
        inc     hl                                             ;#7C1C: 23
        ld      a,(hl)                                         ;#7C1D: 7E
        cp      ":"                                            ;#7C1E: FE 3A
        jr      nz,SAVELOAD_FILENAME_NO_PREFIX                 ;#7C20: 20 05
        pop     bc                                             ;#7C22: C1
        push    af                                             ;#7C23: F5
        inc     hl                                             ;#7C24: 23
        jr      SAVELOAD_FILENAME_BODY                         ;#7C25: 18 03

SAVELOAD_FILENAME_NO_PREFIX:
        ; No "CAS:" device prefix — pop hl, push 0, fall into SAVELOAD_FILENAME_BODY
        pop     hl                                             ;#7C27: E1
        xor     a                                              ;#7C28: AF
        push    af                                             ;#7C29: F5
SAVELOAD_FILENAME_BODY:
        ; After device prefix, parse the 8-char name into BIOS FCB; handles ',' and '.'
        inc     hl                                             ;#7C2A: 23
        ld      a,(hl)                                         ;#7C2B: 7E
        dec     hl                                             ;#7C2C: 2B
        cp      ":"                                            ;#7C2D: FE 3A
        jr      nz,SAVELOAD_FILENAME_INIT                      ;#7C2F: 20 06
        ld      a,(hl)                                         ;#7C31: 7E
        inc     hl                                             ;#7C32: 23
        inc     hl                                             ;#7C33: 23
        sub     "@"                                            ;#7C34: D6 40
        ld      (de),a                                         ;#7C36: 12
SAVELOAD_FILENAME_INIT:
        ; Slot-prefix done — DE points at FCB name field, init b=8
        inc     de                                             ;#7C37: 13
        push    de                                             ;#7C38: D5
        ld      b,8                                            ;#7C39: 06 08
SAVELOAD_FILENAME_NAME_LOOP:
        ; Per-char copy of up to 8 name chars into FCB
        ld      a,(hl)                                         ;#7C3B: 7E
        or      a                                              ;#7C3C: B7
        jr      nz,SAVELOAD_FILENAME_DELIM                     ;#7C3D: 20 03
SAVELOAD_FILENAME_END:
        ; End-of-name: pop saved DE, fall into SAVELOAD_FILENAME_DONE (pop af; ret)
        pop     de                                             ;#7C3F: D1
SAVELOAD_FILENAME_DONE:
        ; Clean tail of SAVELOAD_PARSE_FILENAME — pop af, ret
        pop     af                                             ;#7C40: F1
        ret                                                    ;#7C41: C9

SAVELOAD_FILENAME_DELIM:
        ; Per-char: test for ',' (end) or '.' (ext) before store
        cp      ","                                            ;#7C42: FE 2C
        jr      z,SAVELOAD_FILENAME_END                        ;#7C44: 28 F9
        cp      "."                                            ;#7C46: FE 2E
        inc     hl                                             ;#7C48: 23
        jr      z,SAVELOAD_FILENAME_EXT                        ;#7C49: 28 11
        ld      (de),a                                         ;#7C4B: 12
        inc     de                                             ;#7C4C: 13
        djnz    SAVELOAD_FILENAME_NAME_LOOP                    ;#7C4D: 10 EC
SAVELOAD_FILENAME_OVERFLOW:
        ; Name exceeded 8 chars — skip remaining until '.' or ','
        ld      a,(hl)                                         ;#7C4F: 7E
        or      a                                              ;#7C50: B7
        jr      z,SAVELOAD_FILENAME_END                        ;#7C51: 28 EC
        cp      ","                                            ;#7C53: FE 2C
        jr      z,SAVELOAD_FILENAME_END                        ;#7C55: 28 E8
        inc     hl                                             ;#7C57: 23
        cp      "."                                            ;#7C58: FE 2E
        jr      nz,SAVELOAD_FILENAME_OVERFLOW                  ;#7C5A: 20 F3
SAVELOAD_FILENAME_EXT:
        ; '.' seen — advance DE to FCB ext field, copy up to 3 chars
        pop     de                                             ;#7C5C: D1
        ld      bc,8                                           ;#7C5D: 01 08 00
        ex      de,hl                                          ;#7C60: EB
        add     hl,bc                                          ;#7C61: 09
        ex      de,hl                                          ;#7C62: EB
        ld      b,3                                            ;#7C63: 06 03
SAVELOAD_FILENAME_EXT_LOOP:
        ; Per-char copy of up to 3 ext chars into FCB
        ld      a,(hl)                                         ;#7C65: 7E
        or      a                                              ;#7C66: B7
        jr      z,SAVELOAD_FILENAME_DONE                       ;#7C67: 28 D7
        cp      ","                                            ;#7C69: FE 2C
        jr      z,SAVELOAD_FILENAME_DONE                       ;#7C6B: 28 D3
        ld      (de),a                                         ;#7C6D: 12
        inc     de                                             ;#7C6E: 13
        inc     hl                                             ;#7C6F: 23
        djnz    SAVELOAD_FILENAME_EXT_LOOP                     ;#7C70: 10 F3
        jr      SAVELOAD_FILENAME_DONE                         ;#7C72: 18 CC

TAPE_BIN_SAVE_START:
        ; Start BSAVE-style tape write: TAPOON, emit 10× 0D0h header bytes, prep for body
        ld      a,1                                            ;#7C74: 3E 01
        call    BIOS_TAPOON                                    ;#7C76: CD EA 00
        jr      c,TAPE_ERROR_EXIT                              ;#7C79: 38 6A
        ld      b,0Ah                                          ;#7C7B: 06 0A
TAPE_BIN_SAVE_HEADER_LOOP:
        ; 10x TAPOUT of 0D0h sync header bytes
        push    bc                                             ;#7C7D: C5
        ld      a,0D0h                                         ;#7C7E: 3E D0
        call    BIOS_TAPOUT                                    ;#7C80: CD ED 00
        pop     bc                                             ;#7C83: C1
        djnz    TAPE_BIN_SAVE_HEADER_LOOP                      ;#7C84: 10 F7
        ld      hl,MEGA_DM_OFFSET                              ;#7C86: 21 38 FA
        ld      b,6                                            ;#7C89: 06 06
TAPE_BIN_SAVE_FILNAM_LOOP:
        ; 6x TAPOUT of filename bytes after sync
        push    hl                                             ;#7C8B: E5
        push    bc                                             ;#7C8C: C5
        ld      a,(hl)                                         ;#7C8D: 7E
        call    BIOS_TAPOUT                                    ;#7C8E: CD ED 00
        pop     bc                                             ;#7C91: C1
        pop     hl                                             ;#7C92: E1
        inc     hl                                             ;#7C93: 23
        djnz    TAPE_BIN_SAVE_FILNAM_LOOP                      ;#7C94: 10 F5
        xor     a                                              ;#7C96: AF
        call    BIOS_TAPOON                                    ;#7C97: CD EA 00
        jr      c,TAPE_ERROR_EXIT                              ;#7C9A: 38 49
        ld      hl,(MEGA_HEADER_TYPE)                          ;#7C9C: 2A 30 FA
        push    hl                                             ;#7C9F: E5
        call    TAPE_WRITE_WORD_HL                             ;#7CA0: CD D0 7C
        ld      hl,(MEGA_SCRATCH_W2)                           ;#7CA3: 2A 32 FA
        push    hl                                             ;#7CA6: E5
        call    TAPE_WRITE_WORD_HL                             ;#7CA7: CD D0 7C
        ld      hl,(MEGA_SCRATCH_W3)                           ;#7CAA: 2A 34 FA
        call    TAPE_WRITE_WORD_HL                             ;#7CAD: CD D0 7C
        pop     de                                             ;#7CB0: D1
        pop     hl                                             ;#7CB1: E1
        inc     de                                             ;#7CB2: 13
        xor     a                                              ;#7CB3: AF
        ld      (MEGA_HOOK_EI_PATCH),a                         ;#7CB4: 32 0E FA
TAPE_BIN_SAVE_LOOP:
        ; TAPE BSAVE: per-byte body — slot-read at HL, write to tape
        push    hl                                             ;#7CB7: E5
        push    de                                             ;#7CB8: D5
        call    MEGA_SLOT_READ_HL                              ;#7CB9: CD 16 FA
        call    BIOS_TAPOUT                                    ;#7CBC: CD ED 00
        pop     de                                             ;#7CBF: D1
        pop     hl                                             ;#7CC0: E1
        jr      c,TAPE_ERROR_EXIT                              ;#7CC1: 38 22
        inc     hl                                             ;#7CC3: 23
        rst     20h                                            ;#7CC4: E7
        jr      nz,TAPE_BIN_SAVE_LOOP                          ;#7CC5: 20 F0
        call    BIOS_TAPOOF                                    ;#7CC7: CD F0 00
        ld      a,0FBh                                         ;#7CCA: 3E FB
        ld      (MEGA_HOOK_EI_PATCH),a                         ;#7CCC: 32 0E FA
        ret                                                    ;#7CCF: C9

TAPE_WRITE_WORD_HL:
        ; Write HL to cassette as two bytes (low byte first) via BIOS_TAPOUT
        ld      a,l                                            ;#7CD0: 7D
        push    hl                                             ;#7CD1: E5
        call    BIOS_TAPOUT                                    ;#7CD2: CD ED 00
        pop     hl                                             ;#7CD5: E1
        ld      a,h                                            ;#7CD6: 7C
        jp      BIOS_TAPOUT                                    ;#7CD7: C3 ED 00

TAPE_READ_WORD_HL:
        ; Read HL from cassette as two bytes (low byte first) via BIOS_TAPIN
        call    BIOS_TAPIN                                     ;#7CDA: CD E4 00
        push    af                                             ;#7CDD: F5
        call    BIOS_TAPIN                                     ;#7CDE: CD E4 00
        ld      h,a                                            ;#7CE1: 67
        pop     af                                             ;#7CE2: F1
        ld      l,a                                            ;#7CE3: 6F
        ret                                                    ;#7CE4: C9

TAPE_ERROR_EXIT:
        ; Tape error tail — TAPIOF + restore EI patch + jp SYNTAX_ERROR_LF
        call    BIOS_TAPIOF                                    ;#7CE5: CD E7 00
        ld      a,0FBh                                         ;#7CE8: 3E FB
        ld      (MEGA_HOOK_EI_PATCH),a                         ;#7CEA: 32 0E FA
        jp      SYNTAX_ERROR_LF                                ;#7CED: C3 47 43

LOAD_FILE_OPEN:
        ; File-opening tail used after filename parse; handles both ASCII and binary
        call    BIOS_TAPION                                    ;#7CF0: CD E1 00
        jr      c,TAPE_ERROR_EXIT                              ;#7CF3: 38 F0
        ld      b,0Ah                                          ;#7CF5: 06 0A
LOAD_FILE_SYNC_LOOP:
        ; 10x TAPIN sync header (D0h) verify loop
        push    bc                                             ;#7CF7: C5
        call    BIOS_TAPIN                                     ;#7CF8: CD E4 00
        pop     bc                                             ;#7CFB: C1
        cp      0D0h                                           ;#7CFC: FE D0
        jr      nz,LOAD_FILE_OPEN                              ;#7CFE: 20 F0
        djnz    LOAD_FILE_SYNC_LOOP                            ;#7D00: 10 F5
        ld      b,6                                            ;#7D02: 06 06
        ld      hl,BIOS_FILNAM                                 ;#7D04: 21 66 F8
LOAD_FILE_FILNAM_LOOP:
        ; 6x TAPIN of filename bytes after sync
        push    hl                                             ;#7D07: E5
        push    bc                                             ;#7D08: C5
        call    BIOS_TAPIN                                     ;#7D09: CD E4 00
        pop     bc                                             ;#7D0C: C1
        pop     hl                                             ;#7D0D: E1
        ld      (hl),a                                         ;#7D0E: 77
        inc     hl                                             ;#7D0F: 23
        djnz    LOAD_FILE_FILNAM_LOOP                          ;#7D10: 10 F5
        ld      hl,MEGA_DM_OFFSET                              ;#7D12: 21 38 FA
        ld      a,(hl)                                         ;#7D15: 7E
        cp      " "                                            ;#7D16: FE 20
        jr      z,TAPE_FILE_FOUND_REPORT                       ;#7D18: 28 20
        ld      de,BIOS_FILNAM                                 ;#7D1A: 11 66 F8
        ld      b,6                                            ;#7D1D: 06 06
LOAD_FILE_FILNAM_CMP_LOOP:
        ; 6x compare loaded filename vs requested name
        ld      a,(de)                                         ;#7D1F: 1A
        cp      (hl)                                           ;#7D20: BE
        jr      nz,TAPE_FILE_SKIPPED_REPORT                    ;#7D21: 20 06
        inc     hl                                             ;#7D23: 23
        inc     de                                             ;#7D24: 13
        djnz    LOAD_FILE_FILNAM_CMP_LOOP                      ;#7D25: 10 F8
        jr      TAPE_FILE_FOUND_REPORT                         ;#7D27: 18 11

TAPE_FILE_SKIPPED_REPORT:
        ; Print "Pulei:" + filename + CR, then re-loop via LOAD_FILE_OPEN
        call    PRINT_INLINE_STRING                            ;#7D29: CD 8A 50
        db      "Pulei:"C                                      ;#7D2C: 50 75 6C 65 69 BA
        call    PRINT_TAPE_FILENAME                            ;#7D32: CD 9E 7D
        call    PRINT_CR                                       ;#7D35: CD B4 42
        jr      LOAD_FILE_OPEN                                 ;#7D38: 18 B6

TAPE_FILE_FOUND_REPORT:
        ; Print "Achei:" + filename + CR, then read BSAVE header (start/end/exec)
        call    PRINT_INLINE_STRING                            ;#7D3A: CD 8A 50
        db      "Achei:"C                                      ;#7D3D: 41 63 68 65 69 BA
        call    PRINT_TAPE_FILENAME                            ;#7D43: CD 9E 7D
        call    PRINT_CR                                       ;#7D46: CD B4 42
        call    BIOS_TAPION                                    ;#7D49: CD E1 00
        jr      c,TAPE_ERROR_EXIT                              ;#7D4C: 38 97
        call    TAPE_READ_WORD_HL                              ;#7D4E: CD DA 7C
        ld      (MEGA_HEADER_TYPE),hl                          ;#7D51: 22 30 FA
        push    hl                                             ;#7D54: E5
        call    TAPE_READ_WORD_HL                              ;#7D55: CD DA 7C
        ld      (MEGA_SCRATCH_W2),hl                           ;#7D58: 22 32 FA
        push    hl                                             ;#7D5B: E5
        call    TAPE_READ_WORD_HL                              ;#7D5C: CD DA 7C
        ld      (MEGA_SCRATCH_W3),hl                           ;#7D5F: 22 34 FA
        inc     hl                                             ;#7D62: 23
        ld      a,h                                            ;#7D63: 7C
        or      l                                              ;#7D64: B5
        jr      z,TAPE_LOAD_EDITOR_CHECK                       ;#7D65: 28 06
        call    EDITOR_MODE_TEST                               ;#7D67: CD 36 7E
        jp      z,TAPE_ACCESS_ERROR                            ;#7D6A: CA 0B 69

TAPE_LOAD_EDITOR_CHECK:
        ; TAPE LOAD: exec=0 path — re-test editor mode for buffer setup
        call    EDITOR_MODE_TEST                               ;#7D6D: CD 36 7E
        jr      nz,TAPE_LOAD_BODY_START                        ;#7D70: 20 0C
        ld      hl,(MEGA_HEADER_TYPE)                          ;#7D72: 2A 30 FA
        ld      (MEGA_SRC_BUF_START),hl                        ;#7D75: 22 01 EC
        ld      hl,(MEGA_SCRATCH_W2)                           ;#7D78: 2A 32 FA
        ld      (MEGA_SRC_BUF_HEAD),hl                         ;#7D7B: 22 03 EC
TAPE_LOAD_BODY_START:
        ; TAPE LOAD: clear EI patch, pop end/start addrs, enter byte loop
        xor     a                                              ;#7D7E: AF
        ld      (MEGA_HOOK_EI_PATCH),a                         ;#7D7F: 32 0E FA
        pop     de                                             ;#7D82: D1
        pop     hl                                             ;#7D83: E1
        inc     de                                             ;#7D84: 13
TAPE_LOAD_BYTE_LOOP:
        ; TAPE LOAD: per-byte — read tape, MEGA_SLOT_WRITE, loop to end
        push    hl                                             ;#7D85: E5
        push    de                                             ;#7D86: D5
        call    BIOS_TAPIN                                     ;#7D87: CD E4 00
        pop     de                                             ;#7D8A: D1
        pop     hl                                             ;#7D8B: E1
        jp      c,TAPE_ERROR_EXIT                              ;#7D8C: DA E5 7C
        call    MEGA_SLOT_WRITE                                ;#7D8F: CD 10 FA
        inc     hl                                             ;#7D92: 23
        rst     20h                                            ;#7D93: E7
        jr      nz,TAPE_LOAD_BYTE_LOOP                         ;#7D94: 20 EF
        ld      a,0FBh                                         ;#7D96: 3E FB
        ld      (MEGA_HOOK_EI_PATCH),a                         ;#7D98: 32 0E FA
        jp      BIOS_TAPIOF                                    ;#7D9B: C3 E7 00

PRINT_TAPE_FILENAME:
        ; Print the 6-char tape filename held in BIOS_FILNAM via OUTDO (rst 18h)
        ld      hl,BIOS_FILNAM                                 ;#7D9E: 21 66 F8
        ld      b,6                                            ;#7DA1: 06 06
PRINT_TAPE_FILENAME_LOOP:
        ; 6x rst 18h print of BIOS_FILNAM characters
        ld      a,(hl)                                         ;#7DA3: 7E
        inc     hl                                             ;#7DA4: 23
        rst     18h                                            ;#7DA5: DF
        djnz    PRINT_TAPE_FILENAME_LOOP                       ;#7DA6: 10 FB
        ret                                                    ;#7DA8: C9

MEGA_SAVE_PARSE_RANGE:
        ; Parse SAVE's `,start,end,exec` args; default = full buffer with no exec
        push    af                                             ;#7DA9: F5
        call    SKIP_SPACES                                    ;#7DAA: CD F3 43
        jr      nz,SAVE_PARSE_RANGE_ARGS                       ;#7DAD: 20 33
        ld      hl,(MEGA_SRC_BUF_START)                        ;#7DAF: 2A 01 EC
        ld      (MEGA_HEADER_TYPE),hl                          ;#7DB2: 22 30 FA
        ld      hl,(MEGA_SRC_BUF_HEAD)                         ;#7DB5: 2A 03 EC
        ld      (MEGA_SCRATCH_W2),hl                           ;#7DB8: 22 32 FA
        ld      hl,0FFFFh                                      ;#7DBB: 21 FF FF
        ld      (MEGA_SCRATCH_W3),hl                           ;#7DBE: 22 34 FA
MEGA_SAVE_VALIDATE_RANGE:
        ; Validate save range (start<=end via DCOMPR), raise "Bloco invalido" on bad
        ld      hl,(MEGA_SCRATCH_W2)                           ;#7DC1: 2A 32 FA
        ld      de,(MEGA_HEADER_TYPE)                          ;#7DC4: ED 5B 30 FA
        rst     20h                                            ;#7DC8: E7
        jr      nc,SAVE_RANGE_OK                               ;#7DC9: 30 15
        call    PRINT_INLINE_STRING                            ;#7DCB: CD 8A 50
        db      "Bloco invalido", 8Dh                          ;#7DCE: 42 6C 6F 63 6F 20 69 6E 76 61 6C 69 64 6F 8D
        jp      SYNTAX_ERROR_LF                                ;#7DDD: C3 47 43

SAVE_RANGE_OK:
        ; MEGA_SAVE_VALIDATE_RANGE: start<=end — pop AF and return
        pop     af                                             ;#7DE0: F1
        ret                                                    ;#7DE1: C9

SAVE_PARSE_RANGE_ARGS:
        ; args present — expect ',start,end[,exec]'
        ld      a,(hl)                                         ;#7DE2: 7E
        cp      ","                                            ;#7DE3: FE 2C
        jp      nz,SYNTAX_ERROR_LF                             ;#7DE5: C2 47 43
        call    SKIP_SPACES_ADVANCE                            ;#7DE8: CD F2 43
        call    PARSE_HEX_WORD                                 ;#7DEB: CD BA 50
        jp      c,SYNTAX_ERROR_LF                              ;#7DEE: DA 47 43
        ld      (MEGA_HEADER_TYPE),de                          ;#7DF1: ED 53 30 FA
        ld      (MEGA_SCRATCH_W3),de                           ;#7DF5: ED 53 34 FA
        ld      a,(hl)                                         ;#7DF9: 7E
        or      a                                              ;#7DFA: B7
        jp      z,SYNTAX_ERROR_LF                              ;#7DFB: CA 47 43
        cp      ","                                            ;#7DFE: FE 2C
        jp      nz,SYNTAX_ERROR_LF                             ;#7E00: C2 47 43
        inc     hl                                             ;#7E03: 23
        call    PARSE_HEX_WORD                                 ;#7E04: CD BA 50
        jp      c,SYNTAX_ERROR_LF                              ;#7E07: DA 47 43
        ld      (MEGA_SCRATCH_W2),de                           ;#7E0A: ED 53 32 FA
        call    SKIP_SPACES                                    ;#7E0E: CD F3 43
        jr      z,MEGA_SAVE_VALIDATE_RANGE                     ;#7E11: 28 AE
        cp      ","                                            ;#7E13: FE 2C
        jp      nz,SYNTAX_ERROR_LF                             ;#7E15: C2 47 43
        inc     hl                                             ;#7E18: 23
        call    PARSE_HEX_WORD_AND_EOL                         ;#7E19: CD E1 43
        ld      (MEGA_SCRATCH_W3),de                           ;#7E1C: ED 53 34 FA
        jr      MEGA_SAVE_VALIDATE_RANGE                       ;#7E20: 18 9F

MEGA_PCMD_FILES:
        ; Prompt command "FILES" — invoke BIOS HFILE hook with HOUTD temporarily disabled
        ld      a,Z80_RET                                      ;#7E22: 3E C9
        ld      (BIOS_HOUTD),a                                 ;#7E24: 32 E4 FE
        ld      hl,FILES_RESTORE_HOUTD                         ;#7E27: 21 2E 7E
        push    hl                                             ;#7E2A: E5
        call    BIOS_HFILE                                     ;#7E2B: CD 7B FE
FILES_RESTORE_HOUTD:
        ; Cleanup after BIOS_HFILE returns — restore HOUTD to `jp` variant, print CR
        ld      a,Z80_JP                                       ;#7E2E: 3E C3
        ld      (BIOS_HOUTD),a                                 ;#7E30: 32 E4 FE
        jp      PRINT_CR                                       ;#7E33: C3 B4 42

EDITOR_MODE_TEST:
        ; Load MEGA_EDITOR_MODE_FLAGS, set flags; Z if editor not active (FA36 = 0)
        ld      a,(MEGA_EDITOR_MODE_FLAGS)                     ;#7E36: 3A 36 FA
        or      a                                              ;#7E39: B7
        ret                                                    ;#7E3A: C9

MEGA_CMD_SETGREY:
        ; `CALL SETGREY` handler — set the monochrome/grey palette mode
        pop     hl                                             ;#7E3B: E1
        call    SKIP_SPACES                                    ;#7E3C: CD F3 43
        jr      nz,MEGA_CMD_SETGREY_ARG                        ;#7E3F: 20 02
        scf                                                    ;#7E41: 37
        ret                                                    ;#7E42: C9

MEGA_CMD_SETGREY_ARG:
        ; With arg: evaluate BASIC operand, store low byte in BIOS_RG17SA (palette mode)
        ld      ix,BIOS_EVAL_BASIC_OPERAND                     ;#7E43: DD 21 2F 54
        call    BIOS_CALBAS                                    ;#7E47: CD 59 01
        ld      a,e                                            ;#7E4A: 7B
        ld      (BIOS_RG17SA),a                                ;#7E4B: 32 F0 FF
        and     a                                              ;#7E4E: A7
        ret                                                    ;#7E4F: C9

MEGA_CMD_SETKEY:
        ; `CALL SETKEY` handler — install CALLF stub into BIOS_HKEYC for fn keys
        pop     hl                                             ;#7E50: E1
        call    SKIP_SPACES                                    ;#7E51: CD F3 43
        jr      nz,MEGA_CMD_SETKEY_ARG                         ;#7E54: 20 02
        scf                                                    ;#7E56: 37
        ret                                                    ;#7E57: C9

MEGA_CMD_SETKEY_ARG:
        ; With arg: evaluate BASIC operand, install CALLF stub at BIOS_HKEYC
        ld      ix,BIOS_EVAL_BASIC_OPERAND                     ;#7E58: DD 21 2F 54
        call    BIOS_CALBAS                                    ;#7E5C: CD 59 01
        ld      a,e                                            ;#7E5F: 7B
        or      a                                              ;#7E60: B7
        jr      nz,SETKEY_INSTALL_STUB                         ;#7E61: 20 07
        ld      a,Z80_RET                                      ;#7E63: 3E C9
        ld      (BIOS_HKEYC),a                                 ;#7E65: 32 CC FD
        and     a                                              ;#7E68: A7
        ret                                                    ;#7E69: C9

SETKEY_INSTALL_STUB:
        ; Non-zero arg: LDIR the 5-byte stub into HKEYC, patch slot byte from PPI A8
        di                                                     ;#7E6A: F3
        push    hl                                             ;#7E6B: E5
        ld      hl,SETKEY_HKEYC_TEMPLATE                       ;#7E6C: 21 84 7E
        ld      de,0FDCCh                                      ;#7E6F: 11 CC FD
        ld      bc,5                                           ;#7E72: 01 05 00
        ldir                                                   ;#7E75: ED B0
        in      a,(0A8h)                                       ;#7E77: DB A8
        rrca                                                   ;#7E79: 0F
        rrca                                                   ;#7E7A: 0F
        and     3                                              ;#7E7B: E6 03
        ld      (BIOS_HKEYC+1),a                               ;#7E7D: 32 CD FD
        ei                                                     ;#7E80: FB
        pop     hl                                             ;#7E81: E1
        and     a                                              ;#7E82: A7
        ret                                                    ;#7E83: C9

SETKEY_HKEYC_TEMPLATE:
        ; 5-byte HKEYC hook template (RST 30 + slot-stub) copied to FDCCh by SETKEY
        rst     30h                                            ;#7E84: F7
        db      0                                              ;#7E85: 00
        dw      SETKEY_HKEYC_HANDLER                           ;#7E86: 8F 7E
        ret                                                    ;#7E88: C9

MEGA_CMD_DUMP:
        ; `CALL DUMP` handler — printer memory-dump command
        call    MEGA_DUMP_BODY                                 ;#7E89: CD 92 7E
        pop     hl                                             ;#7E8C: E1
        and     a                                              ;#7E8D: A7
        ret                                                    ;#7E8E: C9

SETKEY_HKEYC_HANDLER:
        ; HKEYC hook body invoked by SETKEY template — falls into DUMP if key=':'
        cp      ":"                                            ;#7E8F: FE 3A
        ret     nz                                             ;#7E91: C0
MEGA_DUMP_BODY:
        ; Push registers, save SP to FA3Ah, then run the dump loop
        push    af                                             ;#7E92: F5
        push    bc                                             ;#7E93: C5
        push    de                                             ;#7E94: D5
        push    hl                                             ;#7E95: E5
        ld      (MEGA_EDITOR_DATA_BASE),sp                     ;#7E96: ED 73 3A FA
        xor     a                                              ;#7E9A: AF
        ld      c,a                                            ;#7E9B: 4F
        ld      (MEGA_DM_OFFSET),a                             ;#7E9C: 32 38 FA
        call    DUMP_INIT_DISABLE_HKEYC                        ;#7E9F: CD 4B 4E
DUMP_NEXT_COLUMN:
        ; Per-column re-entry — reload SCRMOD and recompute width
        ld      a,(BIOS_SCRMOD)                                ;#7EA2: 3A AF FC
        ld      hl,2D0h                                        ;#7EA5: 21 D0 02
        call    CHECK_GREY_MODE                                ;#7EA8: CD 9A 68
        jr      nz,DUMP_SCRMOD_SETUP                           ;#7EAB: 20 03
        ld      hl,0F0h                                        ;#7EAD: 21 F0 00
DUMP_SCRMOD_SETUP:
        ; Per-screen-mode width/height load (DE = page bytes), SCRMOD-dispatched
        ld      de,628h                                        ;#7EB0: 11 28 06
        or      a                                              ;#7EB3: B7
        jr      z,DUMP_EMIT_PCL_HEADER                         ;#7EB4: 28 0E
        ld      hl,300h                                        ;#7EB6: 21 00 03
        call    CHECK_GREY_MODE                                ;#7EB9: CD 9A 68
        jr      nz,DUMP_SCRMOD_NONGREY                         ;#7EBC: 20 03
        ld      hl,100h                                        ;#7EBE: 21 00 01
DUMP_SCRMOD_NONGREY:
        ; Non-grey SCR1+ branch — set DE=820h (page bytes)
        ld      de,820h                                        ;#7EC1: 11 20 08
DUMP_EMIT_PCL_HEADER:
        ; Emit PCL ESC sequences (1B, "L" or "K", LSB, MSB) to start a bit-image row
        ld      a,1Bh                                          ;#7EC4: 3E 1B
        call    DUMP_BYTE_TO_LPT                               ;#7EC6: CD 8E 7F
        ld      a,4Ch                                          ;#7EC9: 3E 4C
        call    CHECK_GREY_MODE                                ;#7ECB: CD 9A 68
        jr      nz,DUMP_EMIT_PCL_CODE                          ;#7ECE: 20 02
        ld      a,4Bh                                          ;#7ED0: 3E 4B
DUMP_EMIT_PCL_CODE:
        ; Emit selected PCL code (K or L) and width word to LPT
        call    DUMP_BYTE_TO_LPT                               ;#7ED2: CD 8E 7F
        ld      a,l                                            ;#7ED5: 7D
        call    DUMP_BYTE_TO_LPT                               ;#7ED6: CD 8E 7F
        ld      a,h                                            ;#7ED9: 7C
        call    DUMP_BYTE_TO_LPT                               ;#7EDA: CD 8E 7F
        ld      b,0                                            ;#7EDD: 06 00
DUMP_RENDER_LOOP:
        ; Per-cell: RENDER_SCREEN_CELL_GFX, fetch pixels, emit bit-image bytes
        call    RENDER_SCREEN_CELL_GFX                         ;#7EDF: CD E2 66
        push    de                                             ;#7EE2: D5
        push    bc                                             ;#7EE3: C5
        ld      b,d                                            ;#7EE4: 42
        ld      hl,MEGA_EDITOR_CURSOR_POS                      ;#7EE5: 21 39 FA
        ld      de,0                                           ;#7EE8: 11 00 00
        call    CHECK_GREY_MODE                                ;#7EEB: CD 9A 68
        jr      z,DUMP_CELL_BUF_BASE                           ;#7EEE: 28 06
        bit     0,(hl)                                         ;#7EF0: CB 46
        jr      z,DUMP_CELL_BUF_BASE                           ;#7EF2: 28 02
        ld      e," "                                          ;#7EF4: 1E 20
DUMP_CELL_BUF_BASE:
        ; Load HL = MEGA_EDITOR_CELL_BUF + DE offset (zero or " " column shift)
        ld      hl,MEGA_EDITOR_CELL_BUF                        ;#7EF6: 21 3C FA
        add     hl,de                                          ;#7EF9: 19
DUMP_CELL_PIXEL_LOOP:
        ; Per-cell pixel-byte LPT emit loop (PCL dump)
        push    bc                                             ;#7EFA: C5
        push    hl                                             ;#7EFB: E5
        ld      a,4                                            ;#7EFC: 3E 04
        call    CHECK_GREY_MODE                                ;#7EFE: CD 9A 68
        jr      nz,DUMP_EMIT_ROW_LOOP                          ;#7F01: 20 02
        ld      a,8                                            ;#7F03: 3E 08
DUMP_EMIT_ROW_LOOP:
        ; Per-row body within a cell: rotate pixel bits and emit 8 bytes per cell
        push    af                                             ;#7F05: F5
        ld      a,(hl)                                         ;#7F06: 7E
        call    CHECK_GREY_MODE                                ;#7F07: CD 9A 68
        jr      z,DUMP_GREY_PASSTHROUGH                        ;#7F0A: 28 23
        dec     a                                              ;#7F0C: 3D
        push    bc                                             ;#7F0D: C5
        ld      c,a                                            ;#7F0E: 4F
        ld      b,0                                            ;#7F0F: 06 00
        push    hl                                             ;#7F11: E5
        ld      hl,DUMP_BIT_REORDER_TABLE                      ;#7F12: 21 A2 68
        add     hl,bc                                          ;#7F15: 09
        ld      a,(hl)                                         ;#7F16: 7E
        pop     hl                                             ;#7F17: E1
        pop     bc                                             ;#7F18: C1
        rra                                                    ;#7F19: 1F
        rl      b                                              ;#7F1A: CB 10
        rra                                                    ;#7F1C: 1F
        rl      b                                              ;#7F1D: CB 10
        rra                                                    ;#7F1F: 1F
        rl      c                                              ;#7F20: CB 11
        rra                                                    ;#7F22: 1F
        rl      c                                              ;#7F23: CB 11
        push    af                                             ;#7F25: F5
        rra                                                    ;#7F26: 1F
        rl      e                                              ;#7F27: CB 13
        pop     af                                             ;#7F29: F1
        rra                                                    ;#7F2A: 1F
        rl      e                                              ;#7F2B: CB 13
        jr      DUMP_ROW_NEXT                                  ;#7F2D: 18 04

DUMP_GREY_PASSTHROUGH:
        ; Grey-mode arm: skip the 8-bit unpack, just emit the cell byte as-is
        cp      8                                              ;#7F2F: FE 08
        rl      c                                              ;#7F31: CB 11
DUMP_ROW_NEXT:
        ; Cell-row tail: advance HL by 8 (next pattern row), restore regs, loop
        push    de                                             ;#7F33: D5
        ld      de,8                                           ;#7F34: 11 08 00
        add     hl,de                                          ;#7F37: 19
        pop     de                                             ;#7F38: D1
        pop     af                                             ;#7F39: F1
        dec     a                                              ;#7F3A: 3D
        jr      nz,DUMP_EMIT_ROW_LOOP                          ;#7F3B: 20 C8
        call    CHECK_GREY_MODE                                ;#7F3D: CD 9A 68
        jr      z,DUMP_EMIT_TRIPLE                             ;#7F40: 28 08
        ld      a,b                                            ;#7F42: 78
        call    DUMP_BYTE_TO_LPT                               ;#7F43: CD 8E 7F
        ld      a,e                                            ;#7F46: 7B
        call    DUMP_BYTE_TO_LPT                               ;#7F47: CD 8E 7F
DUMP_EMIT_TRIPLE:
        ; Emit 3 colour bytes per pixel-cell (B/E/C) via DUMP_BYTE_TO_LPT
        ld      a,c                                            ;#7F4A: 79
        call    DUMP_BYTE_TO_LPT                               ;#7F4B: CD 8E 7F
        pop     hl                                             ;#7F4E: E1
        pop     bc                                             ;#7F4F: C1
        inc     hl                                             ;#7F50: 23
        djnz    DUMP_CELL_PIXEL_LOOP                           ;#7F51: 10 A7
        pop     bc                                             ;#7F53: C1
        pop     de                                             ;#7F54: D1
        inc     b                                              ;#7F55: 04
        ld      a,b                                            ;#7F56: 78
        cp      e                                              ;#7F57: BB
        jr      nz,DUMP_RENDER_LOOP                            ;#7F58: 20 85
        ld      a,"\r"                                         ;#7F5A: 3E 0D
        call    DUMP_BYTE_TO_LPT                               ;#7F5C: CD 8E 7F
        ld      a,1Bh                                          ;#7F5F: 3E 1B
        call    DUMP_BYTE_TO_LPT                               ;#7F61: CD 8E 7F
        ld      a,4Ah                                          ;#7F64: 3E 4A
        call    DUMP_BYTE_TO_LPT                               ;#7F66: CD 8E 7F
        ld      a,18h                                          ;#7F69: 3E 18
        call    DUMP_BYTE_TO_LPT                               ;#7F6B: CD 8E 7F
        call    CHECK_GREY_MODE                                ;#7F6E: CD 9A 68
        jr      z,DUMP_CELL_ADVANCE                            ;#7F71: 28 0F
        ld      a,(MEGA_EDITOR_CURSOR_POS)                     ;#7F73: 3A 39 FA
        bit     0,a                                            ;#7F76: CB 47
        jr      z,DUMP_CURSOR_TOGGLE                           ;#7F78: 28 01
        inc     c                                              ;#7F7A: 0C
DUMP_CURSOR_TOGGLE:
        ; Toggle MEGA_EDITOR_CURSOR_POS bit-0 (grey-mode column flip)
        xor     1                                              ;#7F7B: EE 01
        ld      (MEGA_EDITOR_CURSOR_POS),a                     ;#7F7D: 32 39 FA
        jr      DUMP_CELL_TEST_WIDTH                           ;#7F80: 18 01

DUMP_CELL_ADVANCE:
        ; Advance column counter C, check against width, loop or finish row
        inc     c                                              ;#7F82: 0C
DUMP_CELL_TEST_WIDTH:
        ; Alt entry (skip the inc c) — used by grey-mode toggle path to re-test width
        ld      a,c                                            ;#7F83: 79
        cp      18h                                            ;#7F84: FE 18
        jp      nz,DUMP_NEXT_COLUMN                            ;#7F86: C2 A2 7E
DUMP_FINAL_EXIT:
        ; Pop HL/DE then jp DUMP_EXIT — reached after a successful dump and on LPT error
        pop     hl                                             ;#7F89: E1
        pop     de                                             ;#7F8A: D1
        jp      DUMP_EXIT                                      ;#7F8B: C3 FA 7F

DUMP_BYTE_TO_LPT:
        ; Send A to BIOS_LPTOUT; on printer error, restore SP from FA3Ah and abort
        call    BIOS_LPTOUT                                    ;#7F8E: CD A5 00
        ret     nc                                             ;#7F91: D0
        ld      sp,(MEGA_EDITOR_DATA_BASE)                     ;#7F92: ED 7B 3A FA
        jr      DUMP_FINAL_EXIT                                ;#7F96: 18 F1

PARSE_COPY_ARGS:
        ; Parse `(src,dst,len)` numeric expressions via BIOS_CALBAS → FA30/FA32/FA34
        call    SKIP_SPACES                                    ;#7F98: CD F3 43
        jr      z,PARSE_COPY_ARGS_FAIL                         ;#7F9B: 28 39
        cp      "("                                            ;#7F9D: FE 28
        jr      nz,PARSE_COPY_ARGS_FAIL                        ;#7F9F: 20 35
        inc     hl                                             ;#7FA1: 23
        ld      ix,BIOS_EVAL_BASIC_OPERAND                     ;#7FA2: DD 21 2F 54
        call    BIOS_CALBAS                                    ;#7FA6: CD 59 01
        ld      (MEGA_HEADER_TYPE),de                          ;#7FA9: ED 53 30 FA
        ld      a,(hl)                                         ;#7FAD: 7E
        cp      ","                                            ;#7FAE: FE 2C
        jr      nz,PARSE_COPY_ARGS_FAIL                        ;#7FB0: 20 24
        inc     hl                                             ;#7FB2: 23
        ld      ix,BIOS_EVAL_BASIC_OPERAND                     ;#7FB3: DD 21 2F 54
        call    BIOS_CALBAS                                    ;#7FB7: CD 59 01
        ld      (MEGA_SCRATCH_W2),de                           ;#7FBA: ED 53 32 FA
        ld      a,(hl)                                         ;#7FBE: 7E
        cp      ","                                            ;#7FBF: FE 2C
        jr      nz,PARSE_COPY_ARGS_FAIL                        ;#7FC1: 20 13
        inc     hl                                             ;#7FC3: 23
        ld      ix,BIOS_EVAL_BASIC_OPERAND                     ;#7FC4: DD 21 2F 54
        call    BIOS_CALBAS                                    ;#7FC8: CD 59 01
        ld      (MEGA_SCRATCH_W3),de                           ;#7FCB: ED 53 34 FA
        ld      a,(hl)                                         ;#7FCF: 7E
        cp      ")"                                            ;#7FD0: FE 29
        jr      nz,PARSE_COPY_ARGS_FAIL                        ;#7FD2: 20 02
        inc     hl                                             ;#7FD4: 23
        ret                                                    ;#7FD5: C9

PARSE_COPY_ARGS_FAIL:
        ; Error: scf, pop hl (drop caller frame), ret — aborts to grandparent with CF=1
        scf                                                    ;#7FD6: 37
        pop     hl                                             ;#7FD7: E1
        ret                                                    ;#7FD8: C9

MEGA_RETURN_TO_BASIC:
        ; Restore BIOS_DIRBUF from saved cell, call RESTORE_HKEYC, restore HL
        ld      hl,(MEGA_DIRBUF_SAV)                           ;#7FD9: 2A C1 EC
        ld      (BIOS_DIRBUF),hl                               ;#7FDC: 22 51 F3
        call    RESTORE_HKEYC                                  ;#7FDF: CD F3 7F
        ld      hl,(MEGA_SAVED_HL)                             ;#7FE2: 2A FA F9
        or      a                                              ;#7FE5: B7
        ret                                                    ;#7FE6: C9

INSTALL_HKEYC_NULL:
        ; Save current HKEYC (FDCCh) to FFD9h, then write `ret` (C9h) to FDCCh
        ld      a,(BIOS_HKEYC)                                 ;#7FE7: 3A CC FD
        ld      (MEGA_HKEYC_SAVE),a                            ;#7FEA: 32 D9 FF
        ld      a,Z80_RET                                      ;#7FED: 3E C9
        ld      (BIOS_HKEYC),a                                 ;#7FEF: 32 CC FD
        ret                                                    ;#7FF2: C9

RESTORE_HKEYC:
        ; Restore HKEYC (FDCCh) from FFD9h — paired with INSTALL_HKEYC_NULL
        ld      a,(MEGA_HKEYC_SAVE)                            ;#7FF3: 3A D9 FF
        ld      (BIOS_HKEYC),a                                 ;#7FF6: 32 CC FD
        ret                                                    ;#7FF9: C9

DUMP_EXIT:
        ; MEGA_DUMP exit tail: restore HKEYC, pop saved BC/AF, ret to caller
        call    RESTORE_HKEYC                                  ;#7FFA: CD F3 7F
        pop     bc                                             ;#7FFD: C1
        pop     af                                             ;#7FFE: F1
        ret                                                    ;#7FFF: C9

END_POINTER:
        end
