;;; ============================================================
;;; Alert Dialog Definition
;;;
;;; Call `Alert` with A,X = `AlertParams` struct
;;;
;;; Requires the following proc definitions:
;;; * `Bell`
;;; * `SystemTask`
;;; Requires the following data definitions:
;;; * `alert_grafport`
;;; Requires the following macro definitions:
;;; * `MGTK_CALL`
;;; * `BTK_CALL`
;;; Optionally define:
;;; * `AD_YESNOALL` (if defined, yes/no/all buttons supported)
;;; * `AD_SAVEBG` (if defined, background saved/restored)
;;; * `AD_EJECTABLE` (if defined, polls for certain messages)
;;; If `AD_EJECTABLE`. requires `WaitForDiskOrEsc` and `ejectable_flag`
;;; ============================================================

.proc Alert
        jmp     start

question_bitmap:
        PIXELS  "....................................."
        PIXELS  ".###########........................."
        PIXELS  ".###########........................."
        PIXELS  ".###########........................."
        PIXELS  ".###########.........#########......."
        PIXELS  ".####..#####......###############...."
        PIXELS  ".####..#####.....####.........####..."
        PIXELS  ".####..#####....####...........####.."
        PIXELS  ".###########....####...#####...####.."
        PIXELS  ".###########....####...#####...####.."
        PIXELS  ".###########....############...####.."
        PIXELS  ".###########....###########...#####.."
        PIXELS  ".###########....##########...######.."
        PIXELS  ".###########....#########...#######.."
        PIXELS  ".###########....########...########.."
        PIXELS  ".###########....#######...#########.."
        PIXELS  ".###########....#######...#########.."
        PIXELS  ".#####..........###################.."
        PIXELS  ".########.......#######...########..."
        PIXELS  ".########......########...#######...."
        PIXELS  ".###........##################......."
        PIXELS  ".########............................"
        PIXELS  ".########............................"
        PIXELS  "....................................."

exclamation_bitmap:
        PIXELS  "....................................."
        PIXELS  ".###########........................."
        PIXELS  ".###########........................."
        PIXELS  ".###########........................."
        PIXELS  ".###########.........#########......."
        PIXELS  ".####..#####......###############...."
        PIXELS  ".####..#####.....######....#######..."
        PIXELS  ".####..#####....#######....########.."
        PIXELS  ".###########....#######....########.."
        PIXELS  ".###########....#######....########.."
        PIXELS  ".###########....#######....########.."
        PIXELS  ".###########....#######....########.."
        PIXELS  ".###########....#######....########.."
        PIXELS  ".###########....#######....########.."
        PIXELS  ".###########....#######....########.."
        PIXELS  ".###########....#######....########.."
        PIXELS  ".###########....###################.."
        PIXELS  ".#####..........#######....########.."
        PIXELS  ".########.......#######....#######..."
        PIXELS  ".########......##################...."
        PIXELS  ".###........##################......."
        PIXELS  ".########............................"
        PIXELS  ".########............................"
        PIXELS  "....................................."

        kAlertXMargin = 20

.params alert_bitmap_params
        DEFINE_POINT viewloc, kAlertRectLeft + kAlertXMargin, kAlertRectTop + 8
mapbits:        .addr   SELF_MODIFIED
mapwidth:       .byte   6
reserved:       .byte   0
        DEFINE_RECT maprect, 0, 0, 36, 23
        REF_MAPINFO_MEMBERS
.endparams

pencopy:        .byte   MGTK::pencopy
notpencopy:     .byte   MGTK::notpencopy

event_params:   .tag    MGTK::Event
event_kind      := event_params + MGTK::Event::kind
event_coords    := event_params + MGTK::Event::xcoord
event_xcoord    := event_params + MGTK::Event::xcoord
event_ycoord    := event_params + MGTK::Event::ycoord
event_key       := event_params + MGTK::Event::key

;;; Bounds of the alert "window"
kAlertRectWidth         = 420
kAlertRectHeight        = 55
kAlertRectLeft          = (::kScreenWidth - kAlertRectWidth)/2
kAlertRectTop           = (::kScreenHeight - kAlertRectHeight)/2

;;; Window frame is outside the rect proper
kAlertFrameLeft = kAlertRectLeft - 1
kAlertFrameTop = kAlertRectTop - 1
kAlertFrameWidth = kAlertRectWidth + 2
kAlertFrameHeight = kAlertRectHeight + 2
        DEFINE_RECT_SZ alert_rect, kAlertFrameLeft, kAlertFrameTop, kAlertFrameWidth, kAlertFrameHeight

;;; Inner frame
pensize_normal: .byte   1, 1
pensize_frame:  .byte   kBorderDX, kBorderDY
        DEFINE_RECT_SZ alert_inner_frame_rect, kAlertRectLeft + kBorderDX, kAlertRectTop + kBorderDY, kAlertRectWidth - kBorderDX*3 + 1, kAlertRectHeight - kBorderDY*3 + 1

.params screen_portbits
        DEFINE_POINT viewloc, 0, 0
mapbits:        .addr   MGTK::screen_mapbits
mapwidth:       .byte   MGTK::screen_mapwidth
reserved:       .byte   0
        DEFINE_RECT maprect, 0, 0, kScreenWidth-1, kScreenHeight-1
        REF_MAPINFO_MEMBERS
.endparams

;;; --------------------------------------------------

        kAlertButtonTop = kAlertRectTop + 37

        DEFINE_BUTTON ok_rec,        0, res_string_button_ok, kGlyphReturn, kAlertRectLeft + 300, kAlertButtonTop
        DEFINE_BUTTON try_again_rec, 0, res_string_button_try_again, res_char_button_try_again_shortcut, kAlertRectLeft + 300, kAlertButtonTop
        DEFINE_BUTTON cancel_rec,    0, res_string_button_cancel, res_string_button_cancel_shortcut, kAlertRectLeft + 20, kAlertButtonTop
        DEFINE_BUTTON_PARAMS ok_params, ok_rec
        DEFINE_BUTTON_PARAMS try_again_params, try_again_rec
        DEFINE_BUTTON_PARAMS cancel_params, cancel_rec

.ifdef AD_YESNOALL
        DEFINE_BUTTON yes_rec,  0, res_string_button_yes, res_char_button_yes_shortcut, kAlertRectLeft + 175, kAlertButtonTop, 65
        DEFINE_BUTTON no_rec,   0, res_string_button_no,  res_char_button_no_shortcut,  kAlertRectLeft + 255, kAlertButtonTop, 65
        DEFINE_BUTTON all_rec,  0, res_string_button_all, res_char_button_all_shortcut, kAlertRectLeft + 335, kAlertButtonTop, 65
        DEFINE_BUTTON_PARAMS yes_params, yes_rec
        DEFINE_BUTTON_PARAMS no_params, no_rec
        DEFINE_BUTTON_PARAMS all_params, all_rec
.endif ; AD_YESNOALL

        kTextLeft = kAlertRectLeft + 75
        kTextRight = kAlertRectWidth - kAlertXMargin

        kWrapWidth = kTextRight - kTextLeft

        DEFINE_POINT pos_prompt1, kTextLeft, kAlertRectTop + 29-11
        DEFINE_POINT pos_prompt2, kTextLeft, kAlertRectTop + 29

.params textwidth_params        ; Used for spitting/drawing the text.
data:   .addr   0
length: .byte   0
width:  .word   0
.endparams
len:    .byte   0               ; total string length
split_pos:                      ; last known split position
        .byte   0

.params alert_params
text:           .addr   0
buttons:        .byte   0       ; AlertButtonOptions
options:        .byte   0       ; AlertOptions flags
.endparams
.assert .sizeof(alert_params) = .sizeof(AlertParams), error, "struct mismatch"

        kShortcutTryAgain = res_char_button_try_again_shortcut

.ifdef AD_YESNOALL
        kShortcutYes      = res_char_button_yes_shortcut
        kShortcutNo       = res_char_button_no_shortcut
        kShortcutAll      = res_char_button_all_shortcut
.endif ; AD_YESNOALL

        ;; Actual entry point
start:
        ;; Copy passed params
        stax    @addr
        ldx     #.sizeof(AlertParams)-1
        @addr := *+1
:       lda     SELF_MODIFIED,x
        sta     alert_params,x
        dex
        bpl     :-

        MGTK_CALL MGTK::SetCursor, MGTK::SystemCursor::pointer

        ;; --------------------------------------------------
        ;; Draw alert

        MGTK_CALL MGTK::HideCursor

.ifdef AD_SAVEBG
        bit     alert_params::options
    IF_VS                       ; V = use save area
        ;; Compute save bounds
        ldax    #kAlertFrameLeft
        jsr     CalcXSaveBounds
        sty     save_x1_byte
        sta     save_x1_bit

        ldax    #kAlertFrameLeft + kAlertFrameWidth
        jsr     CalcXSaveBounds
        sty     save_x2_byte
        sta     save_x2_bit

        lda     #kAlertFrameTop
        sta     save_y1
        lda     #kAlertFrameTop + kAlertFrameHeight
        sta     save_y2

        jsr     DialogBackgroundSave
    END_IF
.endif ; AD_SAVEBG

        ;; Set up GrafPort - all drawing is in screen coordinates
        MGTK_CALL MGTK::InitPort, alert_grafport
        MGTK_CALL MGTK::SetPort, alert_grafport

        ;; --------------------------------------------------
        ;; Draw alert box and bitmap

        MGTK_CALL MGTK::SetPenMode, pencopy
        MGTK_CALL MGTK::PaintRect, alert_rect ; alert background
        MGTK_CALL MGTK::SetPenMode, notpencopy
        MGTK_CALL MGTK::FrameRect, alert_rect ; alert outline

        MGTK_CALL MGTK::SetPenMode, notpencopy
        MGTK_CALL MGTK::SetPenSize, pensize_frame
        MGTK_CALL MGTK::FrameRect, alert_inner_frame_rect
        MGTK_CALL MGTK::SetPenSize, pensize_normal

        ldax    #exclamation_bitmap
        ldy     alert_params::buttons
    IF_NOT_ZERO
        ldax    #question_bitmap
    END_IF
        stax    alert_bitmap_params::mapbits
        MGTK_CALL MGTK::SetPenMode, pencopy
        MGTK_CALL MGTK::PaintBitsHC, alert_bitmap_params

        ;; --------------------------------------------------
        ;; Draw appropriate buttons

.ifdef AD_EJECTABLE
        bit     ejectable_flag
        jmi     done_buttons
.endif

        bit     alert_params::buttons ; high bit clear = OK only
        bpl     draw_ok_btn

        ;; Cancel button
        BTK_CALL BTK::Draw, cancel_params

        bit     alert_params::buttons ; V bit set = Cancel + OK
        bvs     draw_ok_btn

.ifdef AD_YESNOALL
        ;; Yes/No/All?
        lda     alert_params::buttons
        and     #$0F
    IF_NOT_ZERO
        BTK_CALL BTK::Draw, yes_params
        BTK_CALL BTK::Draw, no_params
        BTK_CALL BTK::Draw, all_params
        jmp     done_buttons
    END_IF
.endif

        ;; Try Again button
        BTK_CALL BTK::Draw, try_again_params
        jmp     done_buttons

        ;; OK button
draw_ok_btn:
        BTK_CALL BTK::Draw, ok_params

done_buttons:

        ;; --------------------------------------------------
        ;; Prompt string
.scope
        ;; Measure for splitting
        ldxy    alert_params::text
        inxy
        stxy    textwidth_params::data

        ptr := $06
        copy16  alert_params::text, ptr
        ldy     #0
        sty     split_pos       ; initialize
        lda     (ptr),y
        sta     len             ; total length

        ;; Search for space or end of string
advance:
:       iny
        cpy     len
        beq     test
        lda     (ptr),y
        cmp     #' '
        bne     :-

        ;; Does this much fit?
test:   sty     textwidth_params::length
        MGTK_CALL MGTK::TextWidth, textwidth_params
        cmp16   textwidth_params::width, #kWrapWidth
        bcs     split           ; no! so we know where to split now

        ;; Yes, record possible split position, maybe continue.
        ldy     textwidth_params::length
        sty     split_pos
        cpy     len             ; hit end of string?
        bne     advance         ; no, keep looking

        ;; Whole string fits, just draw it.
        copy    len, textwidth_params::length
        MGTK_CALL MGTK::MoveTo, pos_prompt2
        MGTK_CALL MGTK::DrawText, textwidth_params
        jmp     done

        ;; Split string over two lines.
split:  copy    split_pos, textwidth_params::length
        MGTK_CALL MGTK::MoveTo, pos_prompt1
        MGTK_CALL MGTK::DrawText, textwidth_params
        lda     textwidth_params::data
        clc
        adc     split_pos
        sta     textwidth_params::data
        bcc     :+
        inc     textwidth_params::data + 1
:       lda     len
        sec
        sbc     split_pos
        sta     textwidth_params::length
        MGTK_CALL MGTK::MoveTo, pos_prompt2
        MGTK_CALL MGTK::DrawText, textwidth_params

done:
.endscope
        MGTK_CALL MGTK::ShowCursor

        ;; --------------------------------------------------
        ;; Play bell

        bit     alert_params::options
    IF_NS                       ; N = play sound
        jsr     Bell
    END_IF

        ;; --------------------------------------------------
        ;; Event Loop

event_loop:
.ifdef AD_EJECTABLE
        bit     ejectable_flag
    IF_NS
        jsr     WaitForDiskOrEsc
        bne     :+
        jmp     finish_ok
:       jmp     finish_cancel
    END_IF
.endif ; AD_EJECTABLE

        jsr     SystemTask
        MGTK_CALL MGTK::GetEvent, event_params
        lda     event_kind
        cmp     #MGTK::EventKind::button_down
        jeq     HandleButtonDown

        cmp     #MGTK::EventKind::key_down
        bne     event_loop

        ;; --------------------------------------------------
        ;; Key Down
        lda     event_key
        jsr     ToUpperCase

        bit     alert_params::buttons ; high bit clear = OK only
        bpl     check_only_ok

        cmp     #CHAR_ESCAPE
        bne     :+

        ;; Cancel
        BTK_CALL BTK::Flash, cancel_params
finish_cancel:
        lda     #kAlertResultCancel
        jmp     finish

:       bit     alert_params::buttons ; V bit set = Cancel + OK
        bvs     check_ok

.ifdef AD_YESNOALL
        pha
        lda     alert_params::buttons
        and     #$0F
    IF_NOT_ZERO
        pla
        cmp     #kShortcutNo
        bne     :+
        BTK_CALL BTK::Flash, no_params
        lda     #kAlertResultNo
        jmp     finish
:
        cmp     #kShortcutYes
        bne     :+
        BTK_CALL BTK::Flash, yes_params
        lda     #kAlertResultYes
        jmp     finish
:
        cmp     #kShortcutAll
        bne     :+
        BTK_CALL BTK::Flash, all_params
        lda     #kAlertResultAll
        jmp     finish
:
        jmp     event_loop
    END_IF
        pla
.endif ; AD_YESNOALL

        cmp     #kShortcutTryAgain
        bne     :+
do_try_again:
        BTK_CALL BTK::Flash, try_again_params
        lda     #kAlertResultTryAgain
        jmp     finish
:
        cmp     #CHAR_RETURN    ; also allow Return as default
        beq     do_try_again
        jmp     event_loop

check_only_ok:
        cmp     #CHAR_ESCAPE    ; also allow Escape as default
        beq     do_ok
check_ok:
        cmp     #CHAR_RETURN
        jne     event_loop

do_ok:  BTK_CALL BTK::Flash, ok_params
finish_ok:
        lda     #kAlertResultOK
        jmp     finish          ; not a fixed value, cannot BNE/BEQ

        ;; --------------------------------------------------
        ;; Buttons

HandleButtonDown:
        MGTK_CALL MGTK::MoveTo, event_coords

        bit     alert_params::buttons ; high bit clear = OK only
        jpl     check_ok_rect

        ;; Cancel
        MGTK_CALL MGTK::InRect, cancel_rec+BTK::ButtonRecord::rect
        cmp     #MGTK::inrect_inside
        bne     :+
        BTK_CALL BTK::Track, cancel_params
        jne     no_button
        lda     #kAlertResultCancel
        .assert kAlertResultCancel <> 0, error, "kAlertResultCancel must be non-zero"
        bne     finish          ; always

:       bit     alert_params::buttons  ; V bit set = Cancel + OK
        bvs     check_ok_rect

.ifdef AD_YESNOALL
        lda     alert_params::buttons
        and     #$0F
    IF_NOT_ZERO
        ;; Yes & No & All
        MGTK_CALL MGTK::InRect, yes_rec+BTK::ButtonRecord::rect
        cmp     #MGTK::inrect_inside
        bne     :+
        BTK_CALL BTK::Track, yes_params
        bne     no_button
        lda     #kAlertResultYes
        .assert kAlertResultYes <> 0, error, "constant mismatch"
        bne     finish          ; always
:
        MGTK_CALL MGTK::InRect, no_rec+BTK::ButtonRecord::rect
        cmp     #MGTK::inrect_inside
        bne     :+
        BTK_CALL BTK::Track, no_params
        bne     no_button
        lda     #kAlertResultNo
        .assert kAlertResultNo <> 0, error, "constant mismatch"
        bne     finish          ; always
:
        MGTK_CALL MGTK::InRect, all_rec+BTK::ButtonRecord::rect
        cmp     #MGTK::inrect_inside
        bne     no_button
        BTK_CALL BTK::Track, all_params
        bne     no_button
        lda     #kAlertResultAll
        .assert kAlertResultAll <> 0, error, "constant mismatch"
        bne     finish          ; always
    END_IF
.endif

        ;; Try Again
        MGTK_CALL MGTK::InRect, try_again_rec+BTK::ButtonRecord::rect
        cmp     #MGTK::inrect_inside
        bne     no_button
        BTK_CALL BTK::Track, try_again_params
        bne     no_button
        lda     #kAlertResultTryAgain
        .assert kAlertResultTryAgain = 0, error, "kAlertResultTryAgain must be non-zero"
        beq     finish          ; always

        ;; OK
check_ok_rect:
        MGTK_CALL MGTK::InRect, ok_rec+BTK::ButtonRecord::rect
        cmp     #MGTK::inrect_inside
        bne     no_button
        BTK_CALL BTK::Track, ok_params
        bne     no_button
        lda     #kAlertResultOK
        .assert kAlertResultOK <> 0, error, "constant mismatch"
        bne     finish          ; always

no_button:
        jmp     event_loop

;;; ============================================================

finish:
.ifdef AD_SAVEBG
        bit     alert_params::options
    IF_VS                       ; V = use save area
        pha
        MGTK_CALL MGTK::HideCursor
        jsr     DialogBackgroundRestore
        MGTK_CALL MGTK::ShowCursor
        pla
    END_IF
.else
        pha
        MGTK_CALL MGTK::SetPortBits, screen_portbits
        MGTK_CALL MGTK::SetPenMode, pencopy
        MGTK_CALL MGTK::PaintRect, alert_rect
        pla
.endif ; AD_SAVEBG
        rts

;;; ============================================================

.ifdef AD_SAVEBG
        .include "savedialogbackground.s"
        DialogBackgroundSave := dialog_background::Save
        DialogBackgroundRestore := dialog_background::Restore
.endif ; AD_SAVEBG

;;; ============================================================

        .include "uppercase.s"

.endproc ; Alert
