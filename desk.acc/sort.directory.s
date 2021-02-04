;;; ============================================================
;;; SORT.DIRECTORY - Desk Accessory
;;;
;;; Sorts the contents of the directory (current window).
;;; If there is a selection, selected files are placed first
;;; following selection order. If there is no selection, all
;;; files are sorted by type then by name.
;;; ============================================================

        .include "../config.inc"

        .include "apple2.inc"
        .include "../inc/apple2.inc"
        .include "../inc/macros.inc"
        .include "../inc/prodos.inc"
        .include "../mgtk/mgtk.inc"
        .include "../common.inc"
        .include "../desktop/desktop.inc"
        .include "../desktop/icontk.inc"

;;; ============================================================
;;; Memory map
;;;
;;;              Main           Aux
;;;          :           : :           :
;;;          |           | |           |
;;;          | DHR       | | DHR       |
;;;  $2000   +-----------+ +-----------+
;;;          | IO Buffer | |Win Tables |
;;;  $1C00   +-----------+ |           |
;;;  $1B00   |           | +-----------+
;;;          |           | |           |
;;;          |           | |           |
;;;          |           | |           |
;;;          | Dir Buff  | |           |
;;;   $E00   +-----------+ |           |
;;;          |           | |           |
;;;          |           | | (unused)  |
;;;          | DA        | |           |
;;;   $800   +-----------+ +-----------+
;;;          :           : :           :
;;;

;;; ============================================================

        .org DA_LOAD_ADDRESS

dir_data_buffer     := $0E00
        .assert (<dir_data_buffer) = 0, error, "Must be page aligned"

kDirDataBufferLen   = DA_IO_BUFFER - dir_data_buffer

;;; ID of window for directory to sort
window_id := $0A

;;; ============================================================

        jmp     start

;;; unit_num for active window, for block operations
unit_num:
        .byte   0

save_stack:
        .byte   0

;;; ============================================================

start:  tsx
        stx     save_stack
        jmp     start2

.proc exit
        ldx     save_stack
        txs
        lda     window_id
        bne     :+
        rts

:       lda     #>(JUMP_TABLE_SELECT_WINDOW-1)
        pha
        lda     #<(JUMP_TABLE_SELECT_WINDOW-1)
        pha
        lda     window_id
        rts
.endproc

;;; ============================================================
;;; ProDOS Relays

.proc open
        sta     ALTZPOFF
        MLI_CALL OPEN, open_params
        sta     ALTZPON
        rts
.endproc

.proc read
        sta     ALTZPOFF
        MLI_CALL READ, read_params
        sta     ALTZPON
        rts
.endproc

.proc write_block
        sta     ALTZPOFF
        MLI_CALL WRITE_BLOCK, block_params
        sta     ALTZPON
        rts
.endproc

.proc read_block
        sta     ALTZPOFF
        MLI_CALL READ_BLOCK, block_params
        sta     ALTZPON
        rts
.endproc

.proc close
        sta     ALTZPOFF
        MLI_CALL CLOSE, close_params
        sta     ALTZPON
        rts
.endproc

;;; ============================================================
;;; ProDOS call parameter blocks

        DEFINE_SET_MARK_PARAMS set_mark_params, $2B
        DEFINE_READ_BLOCK_PARAMS block_params, 0, 0

        buffer := dir_data_buffer
        kBufferLen = kDirDataBufferLen

        DEFINE_OPEN_PARAMS open_params, path_buf, DA_IO_BUFFER
        DEFINE_READ_PARAMS read_params, buffer, kBufferLen
        DEFINE_WRITE_PARAMS write_params, buffer, kBufferLen
        DEFINE_CLOSE_PARAMS close_params

        DEFINE_GET_FILE_INFO_PARAMS file_info_params, path_buf

path_buf:
        .res    kPathBufferSize, 0

;;; ============================================================
;;; Main DA logic

exit1:  jmp     exit

.proc start2
        ;; Grab top window
        param_call JUMP_TABLE_MGTK_RELAY, MGTK::FrontWindow, window_id
        lda     window_id       ; any window open?
        beq     exit1           ; nope, bail

        cmp     #kMaxDeskTopWindows+1 ; is it DeskTop window?
        bcs     exit1                 ; nope, bail

        ;; Copy window path to buffer
        ptr := $06

        jsr     JUMP_TABLE_GET_WIN_PATH
        stax    ptr
        ldy     #0
        lda     (ptr),y
        tay
:       lda     (ptr),y
        sta     path_buf,y
        dey
        bpl     :-

        ;; Fall through...
.endproc

.proc read_sort_write

        ptr := $06

        ;; --------------------------------------------------
        ;; Read the directory (up to 14 blocks)
.scope read

        jsr     open
        bne     exit1
        lda     open_params::ref_num
        sta     read_params::ref_num
        sta     close_params::ref_num

        ;; Save last accessed device's unit_num for block operations.
        copy    DEVNUM, unit_num

        jsr     read
        jsr     close
        bne     exit1
        ldx     #2

        ;; Process "blocks"
loop:
        buf_ptr1_hi := *+2
        lda     buffer + 2

        sta     block_num_table,x

        buf_ptr2_hi := *+2
        lda     buffer + 3

        sta     block_num_table+1,x

        ora     block_num_table,x
        beq     :+

        ;; Move to next "block"
        inc     buf_ptr1_hi
        inc     buf_ptr1_hi
        inc     buf_ptr2_hi
        inc     buf_ptr2_hi

        inx
        inx
        cpx     #>kDirDataBufferLen
        bne     loop

        ;; Prepare for sorting
:       txa
        clc
        adc     #>dir_data_buffer
        sta     end_block_page
        jsr     set_ptr_to_first_entry

:       jsr     set_ptr_to_next_entry
        bcs     jmp_exit
        ldy     #0
        lda     (ptr),y
        and     #STORAGE_TYPE_MASK ; skip deleted entries
        beq     :-
        ldy     #SubdirectoryHeader::file_count
        copy16in (ptr),y, block_num_table
.endscope

        ;; --------------------------------------------------
        ;; Sort the directory entries

        jsr     bubble_sort

        ;; --------------------------------------------------
        ;; Write the directory back out

.scope write
        copy    unit_num, block_params::unit_num
        copy    #0, block_index

        ;; Write the blocks listed in the table out.
loop1:  lda     block_index
        asl     a
        tay
        copy16  block_num_table,y, block_params::block_num
        ora     block_params::block_num ; done?
        beq     update_dir_blocks

        tya                     ; Find address of block data
        clc
        adc     #>dir_data_buffer
        sta     block_params::data_buffer+1
        copy    #0, block_params::data_buffer
        jsr     write_block     ; Write it out
        bne     jmp_exit
        inc     block_index
        bne     loop1

jmp_exit:
        jmp     exit

        block_buf := DA_IO_BUFFER

        ;; For subdirectories, update parent_pointer/parent_entry_number
        ;; See ProDOS 8 Technical Reference Manual B.2.3 - Subdirectory Headers
update_dir_blocks:
        copy16  #block_buf, block_params::data_buffer
        jsr     set_ptr_to_first_entry
loop2:  jsr     set_ptr_to_next_entry
        bcs     fail
        ldy     #0
        lda     (ptr),y
        and     #STORAGE_TYPE_MASK ; skip deleted entries
        beq     loop2
        cmp     #(ST_LINKED_DIRECTORY << 4) ; skip non-directories
        bne     loop2

        ;; Grab key block, using pointer in directory.
        ldy     #FileEntry::key_pointer
        copy16in (ptr),y, block_params::block_num
        jsr     read_block
        bne     done

        ;; Calculate entry's block index from address
        lda     ptr+1
        sec
        sbc     #>dir_data_buffer
        and     #%11111110      ; /2 to get index, *2 to get table ptr
        tay

        ;; Update pointers and rewrite key block.
        copy16  block_num_table,y, block_buf + SubdirectoryHeader::parent_pointer
        copy    entry_num, block_buf + SubdirectoryHeader::parent_entry_number
        jsr     write_block
        jmp     loop2

fail:   pla                     ; BUG: no matching push (only works due to stack restore) ???
done:   jmp     exit

.endscope
        jmp_exit := write::jmp_exit

.endproc

;;; ============================================================

;;; Device number (needed for writing blocks)
dev_num:
        .byte   0

;;; Page (address hi byte) after last block.
end_block_page:
        .byte   0

;;; Block index when writing directory blocks back out.
block_index:
        .byte   0

;;; Table of directory block numbers (words); the directory is read using
;;; file I/O but must be written out using block I/O. The necessary block
;;; numbers to write are extracted and stored here.
block_num_table:
        .res 26, 0

entry_num:
        .byte   0

;;; ============================================================
;;; Bubble sort entries

.proc bubble_sort
        ptr1 := $06
        ptr2 := $08

start:  lda     #0
        sta     flag
        jsr     set_ptr_to_first_entry
        jsr     set_ptr_to_next_entry

loop:   copy16  ptr1, ptr2
        jsr     set_ptr_to_next_entry
        bcs     done

        jsr     compare_file_entries
        bcc     loop
        jsr     swap_entries
        lda     #$FF
        sta     flag
        bne     loop

done:   lda     flag
        bne     start
        rts

flag:   .byte   0
.endproc

;;; ============================================================

.proc set_ptr_to_next_entry
        ptr := $06

        inc     entry_num
        lda     ptr
        clc
        adc     #.sizeof(FileEntry)
        sta     ptr
        bcc     :+
        inc     ptr+1

:       lda     ptr
        cmp     #$FF
        bne     rtcc
        inc     ptr+1
        lda     #1
        sta     entry_num
        lda     #4              ; skip over block header
        sta     ptr
        lda     ptr+1
        cmp     end_block_page
        bcs     rtcs

rtcc:   clc
        rts

rtcs:   sec
        rts
.endproc

;;; ============================================================

.proc set_ptr_to_first_entry
        ptr := $06

        lda     #1
        sta     entry_num
        copy16  #dir_data_buffer + 4, ptr
        rts
.endproc

;;; ============================================================
;;; Swap file entries

.proc swap_entries
        ptr1 := $06
        ptr2 := $08

        ldy     #.sizeof(FileEntry) - 1
loop:   lda     (ptr1),y
        pha
        lda     (ptr2),y
        sta     (ptr1),y
        pla
        sta     (ptr2),y
        dey
        bpl     loop
        rts
.endproc

;;; ============================================================
;;; Compare file entries ($06, $08); order returned in carry.

;;; Uses compare_selection_orders, compare_file_entry_names,
;;; and compare_entry_types_and_names as appropriate.

.proc compare_file_entries
        ptr1 := $06
        ptr2 := $08

        ldy     #0
        lda     (ptr1),y
        and     #STORAGE_TYPE_MASK ; Active file entry?
        bne     :+
        jmp     rtcc

:       lda     (ptr2),y
        and     #STORAGE_TYPE_MASK ; Active file entry?
        bne     :+
        jmp     rtcs

        ;; Are we sorting by selection order?
:       jsr     JUMP_TABLE_GET_SEL_COUNT
        beq     :+              ; No selection, so nope.
        jsr     JUMP_TABLE_GET_SEL_WIN
        cmp     window_id       ; Is selection in the active window?
        bne     :+              ; Nope (desktop or inactive window)
        jmp     compare_selection_orders

:       ldax    ptr2
        jsr     check_system_file
        bcc     rtcc

        ldax    ptr1
        jsr     check_system_file
        bcc     rtcs

        ldy     #0
        lda     (ptr2),y
        and     #STORAGE_TYPE_MASK
        sta     storage_type2

        ldy     #0
        lda     (ptr1),y
        and     #STORAGE_TYPE_MASK
        sta     storage_type1

        ;; Why does this dir-first comparison not just use FT_DIRECTORY ???

        ;; Is #2 a dir?
        lda     storage_type2
        cmp     #(ST_LINKED_DIRECTORY << 4)
        beq     dirs            ; yep, check #1

        ;; Is #1 a dir?
        lda     storage_type1
        cmp     #(ST_LINKED_DIRECTORY << 4)
        beq     rtcs            ; yep, but 2 wasn't, so order
        bne     check_types     ; neither are dirs - check types

        ;; #2 was a dir - is #1?
dirs:   lda     storage_type1
        cmp     #(ST_LINKED_DIRECTORY << 4)
        bne     rtcc

        ;; Both are dirs, order by name
        jsr     compare_file_entry_names
        bcc     rtcc
        bcs     rtcs

        ;; TXT files first
check_types:
        lda     #FT_TEXT
        jsr     compare_entry_types_and_names
        bne     :+
        bcc     rtcc
        bcs     rtcs

        ;; SYS files next
:       lda     #FT_SYSTEM
        jsr     compare_entry_types_and_names
        bne     :+
        bcc     rtcc
        bcs     rtcs

        ;; Then order by type from $FD down
:       lda     #$FD
        sta     type
loop:   dec     type
        lda     type
        beq     rtcc
        jsr     compare_entry_types_and_names
        bne     loop
        bcs     rtcs
        jmp     rtcc

rtcs:   sec
        rts

rtcc:   clc
        rts

storage_type2:
        .byte   0
storage_type1:
        .byte   0
type:   .byte   0
.endproc

;;; ============================================================
;;; Compare selection order of icons; order returned in carry.
;;; Handles either icon being not selected.

.proc compare_selection_orders
        entry_ptr := $10
        filename  := $06
        filename2 := $08

        jsr     JUMP_TABLE_GET_SEL_COUNT
        tax
loop:   dex
        bmi     done1

        ;; Look up next icon, compare length.
        txa
        pha
        jsr     JUMP_TABLE_GET_SEL_ICON
        stax    entry_ptr
        pla
        tax
        add16   entry_ptr, #IconEntry::name, entry_ptr
        ldy     #0
        lda     (entry_ptr),y   ; len
        sta     cmp_len

        lda     (filename),y
        and     #NAME_LENGTH_MASK
        cmp_len := *+1
        cmp     #0
        bne     loop            ; lengths don't match, so not a match

        ;; Bytewise compare names.
        sta     cpy_len
next:   iny

        lda     (entry_ptr),y
        jsr     to_uppercase
        sta     cmp_char

        lda     (filename),y
        jsr     to_uppercase

        cmp_char := *+1
        cmp     #0
        bne     loop            ; no match - try next icon
        cpy_len := *+1
        cpy     #0
        bne     next

done1:  stx     match           ; match, or $FF if none

        jsr     JUMP_TABLE_GET_SEL_COUNT
        tax
loop2:  dex
        bmi     done2

        ;; Look up next icon, compare length.
        txa
        pha
        jsr     JUMP_TABLE_GET_SEL_ICON
        stax    entry_ptr
        pla
        tax
        add16   entry_ptr, #IconEntry::name, entry_ptr
        ldy     #0
        lda     (entry_ptr),y   ; len
        sta     cmp_len2

        lda     (filename2),y
        and     #NAME_LENGTH_MASK
        cmp_len2 := *+1
        cmp     #0
        bne     loop2            ; lengths don't match, so not a match

        ;; Bytewise compare names.
        sta     cpy_len2
next2:  iny

        lda     (entry_ptr),y
        jsr     to_uppercase
        sta     cmp_char2

        lda     (filename2),y
        jsr     to_uppercase

        cmp_char2 := *+1
        cmp     #0
        bne     loop2           ; no match - try next icon
        cpy_len2 := *+1
        cpy     #0
        bne     next2

done2:  stx     match2          ; match, or $FF if none

        lda     match
        and     match2
        cmp     #$FF            ; if either didn't match
        beq     clear
        lda     match2
        cmp     match
        beq     clear           ; if they're the same
        rts                     ; otherwise carry is order

        ;; No match
        sec
        rts

clear:  clc
        rts

match:  .byte   0
match2: .byte   0
.endproc

;;; ============================================================
;;; Compare file types/names ($06, $08 = ptrs, A=type)
;;;
;;; Output: A=$FF if neither matches type; A=$00 and carry is order

.proc compare_entry_types_and_names
        ptr1 := $06
        ptr2 := $08
        kMaxLength = 16

        sta     type0

        ldy     #kMaxLength
        lda     (ptr2),y
        sta     type2
        lda     (ptr1),y
        sta     type1

        lda     type2
        cmp     type0
        beq     :+

        lda     type1
        cmp     type0
        beq     rtcs

        bne     neither

:       lda     type1
        cmp     type0
        bne     rtcc
        jsr     compare_file_entry_names
        bcc     rtcc
        bcs     rtcs

neither:
        return  #$FF

type2:  .byte   0
type1:  .byte   0

rtcc:   lda     #0
        clc
        rts

rtcs:   lda     #0
        sec
        rts

type0:  .byte   0
.endproc

;;; ============================================================
;;; Is the file entry a SYS file with .SYSTEM suffix?
;;; Returns carry clear if true, set if false.

.proc check_system_file
        ptr := $00

        ;; Check for SYS
        stax    ptr
        ldy     #FileEntry::file_type
        lda     (ptr),y
        cmp     #$FF            ; type=SYS
        bne     fail

        ;; Could name end in .SYSTEM?
        ldy     #FileEntry::storage_type_name_length
        lda     (ptr),y
        and     #NAME_LENGTH_MASK
        sec
        sbc     #.strlen(".SYSTEM")-1
        bcc     fail            ; too short
        tay

        ;; Check name suffix
        ldx     #0
        dey
loop:   iny
        inx
        lda     (ptr),y
        and     #CHAR_MASK
        cmp     str_system,x
        bne     fail
        cpx     str_system
        bne     loop

        clc
        rts

fail:   sec
        rts

str_system:
        PASCAL_STRING ".SYSTEM" ; do not localize
.endproc

;;; ============================================================
;;; Compare file entry names; carry indicates order

.proc compare_file_entry_names
        ptr1 := $06
        ptr2 := $08

        ldy     #0
        lda     (ptr2),y
        and     #NAME_LENGTH_MASK
        sta     len2

        sta     len
        lda     (ptr1),y
        and     #NAME_LENGTH_MASK
        sta     len1
        cmp     len
        bcs     :+
        sta     len

:       ldy     #0
loop:   iny
        lda     (ptr2),y
        cmp     (ptr1),y
        beq     next
        bcc     rtcc
rtcs:   sec
        rts

        len := *+1
next:   cpy     #0

        bne     loop
        lda     len2
        cmp     len1
        beq     rtcc
        bcs     rtcs
rtcc:   clc
        rts

len2:   .byte   0
len1:   .byte   0

.endproc

;;; ============================================================
;;; Convert filename character to uppercase

.proc to_uppercase
        and     #CHAR_MASK
        cmp     #'a'            ; Assumes valid filename character
        bcc     :+
        and     #CASE_MASK      ; Make upper-case
:       rts
.endproc

;;; ============================================================

        .assert * <= dir_data_buffer, error, "DA too long"
