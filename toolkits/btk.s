
;;; Routines dirty $06...$2F

.scope btk
        BTKEntry := *

        ;; Points at call parameters
        params_addr := $10

        ;; Cache of static fields from the record
        cache       := $12
        window_id   := cache + BTK::ButtonRecord::window_id
        a_label     := cache + BTK::ButtonRecord::a_label
        a_shortcut  := cache + BTK::ButtonRecord::a_shortcut
        rect        := cache + BTK::ButtonRecord::rect
        state       := cache + BTK::ButtonRecord::state

        ;; Call parameters copied here (0...6 bytes)
        command_data = cache + .sizeof(BTK::ButtonRecord)

        ;; ButtonRecord address, in all param blocks
        a_record = command_data
        update_flag = command_data + 2

        .assert BTKEntry = Dispatch, error, "dispatch addr"
.proc Dispatch

        ;; Adjust stack/stash at `params_addr`
        pla
        sta     params_addr
        clc
        adc     #<3
        tax
        pla
        sta     params_addr+1
        adc     #>3
        pha
        txa
        pha

        ;; Grab command number
        ldy     #1              ; Note: rts address is off-by-one
        lda     (params_addr),y
        pha                     ; A = command number
        asl     a
        tax
        copy16  jump_table,x, jump_addr

        ;; Point `params_addr` at actual params
        iny
        lda     (params_addr),y
        pha
        iny
        lda     (params_addr),y
        sta     params_addr+1
        pla
        sta     params_addr

        lda     #0
        sta     update_flag     ; default for most commands

        ;; Copy param data to `command_data`
        pla                       ; A = command number
        tay
        lda     length_table,y
        tay
        dey
:       copy    (params_addr),y, command_data,y
        dey
        bpl     :-

        ;; Cache static fields from the record, for convenience
        ldy     #.sizeof(BTK::ButtonRecord)-1
:       copy    (a_record),y, cache,y
        dey
        bpl     :-

        jump_addr := *+1
        jmp     SELF_MODIFIED

jump_table:
        .addr   DrawImpl
        .addr   FlashImpl
        .addr   HiliteImpl
        .addr   TrackImpl
.ifndef BTK_SHORT
        .addr   RadioDrawImpl
        .addr   RadioUpdateImpl
        .addr   CheckboxDrawImpl
        .addr   CheckboxUpdateImpl
.endif ; BTK_SHORT

        ;; Must be non-zero
length_table:
        .byte   3               ; Draw
        .byte   2               ; Flash
        .byte   2               ; Hilite
        .byte   2               ; Track
.ifndef BTK_SHORT
        .byte   2               ; RadioDraw
        .byte   2               ; RadioUpdate
        .byte   2               ; CheckboxDraw
        .byte   2               ; CheckboxUpdate
.endif ; BTK_SHORT
.endproc ; Dispatch

;;; ============================================================

penOR:  .byte   MGTK::penOR
penXOR: .byte   MGTK::penXOR
solid_pattern:
        .byte   $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
checkerboard_pattern:
        .byte   $55, $AA, $55, $AA, $55, $AA, $55, $AA

;;; ============================================================

.params getwinport_params
window_id:      .byte   0
port:           .addr   grafport_win
.endparams

grafport_win:   .tag    MGTK::GrafPort

;;; If obscured, execution will not return to the caller.
.proc _SetPort
        bit     update_flag
        bmi     ret

        ;; Set the port
        lda     window_id
        beq     ret
        sta     getwinport_params::window_id
        MGTK_CALL MGTK::GetWinPort, getwinport_params
        bne     obscured
        MGTK_CALL MGTK::SetPort, grafport_win
        beq     ret

obscured:
        pla
        pla
ret:
        rts
.endproc ; _SetPort


;;; ============================================================

.proc DrawImpl
        PARAM_BLOCK params, btk::command_data
a_record  .addr
update    .byte
        END_PARAM_BLOCK
        .assert a_record = params::a_record, error, "a_record must be first"
        .assert update_flag = params::update, error, "param mismatch"

        jsr     _SetPort

        MGTK_CALL MGTK::SetPattern, solid_pattern
        MGTK_CALL MGTK::SetPenMode, penXOR
        MGTK_CALL MGTK::FrameRect, rect

        jmp     HiliteImpl__skip_port

.endproc ; DrawImpl


;;; ============================================================

.proc FlashImpl
        PARAM_BLOCK params, btk::command_data
a_record  .addr
        END_PARAM_BLOCK
        .assert a_record = params::a_record, error, "a_record must be first"

        jsr     _SetPort

        jsr     _Invert
        FALL_THROUGH_TO _Invert
.endproc ; FlashImpl

.proc _Invert
        MGTK_CALL MGTK::SetPenMode, penXOR
        MGTK_CALL MGTK::PaintRect, rect
        rts
.endproc ; _Invert

;;; ============================================================

.proc HiliteImpl
        PARAM_BLOCK params, btk::command_data
a_record  .addr
        END_PARAM_BLOCK
        .assert a_record = params::a_record, error, "a_record must be first"

        jsr     _SetPort
skip_port:

        pos := $0B

        ;; Y-offset from bottom for shorter-than-normal buttons, e.g. arrow glyphs
        sub16_8 rect+MGTK::Rect::y2, #(kButtonHeight - kButtonTextVOffset), pos+MGTK::Point::ycoord

        ldx     #DeskTopSettings::options
        jsr     ReadSetting
        and     #DeskTopSettings::kOptionsShowShortcuts
    IF_NOT_ZERO
        ;; Draw the string (left aligned)
        add16_8 rect+MGTK::Rect::x1, #kButtonTextHOffset, pos+MGTK::Point::xcoord
        MGTK_CALL MGTK::MoveTo, pos
        jsr     _DrawLabel

        ;; Draw the shortcut (if present, right aligned)
        lda     a_shortcut
        ora     a_shortcut+1
      IF_NOT_ZERO
        width := $9
        jsr     _MeasureShortcut
        stax    width
        sub16_8 rect+MGTK::Rect::x2, #kButtonTextHOffset-2, pos+MGTK::Point::xcoord
        sub16   pos+MGTK::Point::xcoord, width, pos+MGTK::Point::xcoord
        MGTK_CALL MGTK::MoveTo, pos
        jsr     _DrawShortcut
      END_IF
    ELSE
        ;; Draw the label (centered)
        width := $9
        jsr     _MeasureLabel
        stax    width

        add16   rect+MGTK::Rect::x1, rect+MGTK::Rect::x2, pos+MGTK::Point::xcoord
        sub16   pos+MGTK::Point::xcoord, width, pos+MGTK::Point::xcoord
        asr16   pos+MGTK::Point::xcoord
        MGTK_CALL MGTK::MoveTo, pos
        jsr     _DrawLabel
    END_IF

        bit     state
    IF_NS
        inc16   rect+MGTK::Rect::x1
        inc16   rect+MGTK::Rect::y1
        dec16   rect+MGTK::Rect::x2
        dec16   rect+MGTK::Rect::y2

        MGTK_CALL MGTK::SetPattern, checkerboard_pattern
        MGTK_CALL MGTK::SetPenMode, penOR
        MGTK_CALL MGTK::PaintRect, rect
    END_IF

        rts
.endproc ; HiliteImpl
HiliteImpl__skip_port := HiliteImpl::skip_port

;;; ============================================================

;;; Input: `a_label` points at string
;;; Trashes $06..$08
.proc _DrawLabel
PARAM_BLOCK dt_params, $6
textptr .addr
textlen .byte
END_PARAM_BLOCK
        ldy     #0
        lda     (a_label),y
        beq     :+
        sta     dt_params::textlen
        ldxy    a_label
        inxy
        stxy    dt_params::textptr
        MGTK_CALL MGTK::DrawText, dt_params
:       rts
.endproc ; _DrawLabel

;;; Inputs: `a_label` points at string
;;; Output: A,X = width
;;; Trashes: $06..$0A
.proc _MeasureLabel
PARAM_BLOCK tw_params, $6
textptr .addr
textlen .byte
width   .word
END_PARAM_BLOCK
        ldy     #0
        lda     (a_label),y
        bne     :+
        lda     #0
        tax
        rts
:
        sta     tw_params::textlen
        ldxy    a_label
        inxy
        stxy    tw_params::textptr
        MGTK_CALL MGTK::TextWidth, tw_params
        ldax    tw_params::width
        rts
.endproc ; _MeasureLabel

;;; Input: `a_shortcut` points at string
;;; Trashes $06..$08
.proc _DrawShortcut
PARAM_BLOCK dt_params, $6
textptr .addr
textlen .byte
END_PARAM_BLOCK
        ldy     #0
        lda     (a_shortcut),y
        beq     :+
        sta     dt_params::textlen
        ldxy    a_shortcut
        inxy
        stxy    dt_params::textptr
        MGTK_CALL MGTK::DrawText, dt_params
:       rts
.endproc ; _DrawShortcut

;;; Inputs: `a_shortcut` points at string
;;; Output: A,X = width
;;; Trashes: $06..$0A
.proc _MeasureShortcut
PARAM_BLOCK tw_params, $6
textptr .addr
textlen .byte
width   .word
END_PARAM_BLOCK
        ldy     #0
        lda     (a_shortcut),y
        bne     :+
        lda     #0
        tax
        rts
:
        sta     tw_params::textlen
        ldxy    a_shortcut
        inxy
        stxy    tw_params::textptr
        MGTK_CALL MGTK::TextWidth, tw_params
        ldax    tw_params::width
        rts
.endproc ; _MeasureShortcut

;;; ============================================================


.proc TrackImpl
        PARAM_BLOCK params, btk::command_data
a_record  .addr
        END_PARAM_BLOCK
        .assert a_record = params::a_record, error, "a_record must be first"

        ;; Use ZP for temporary params
        PARAM_BLOCK event_params, btk::command_data + .sizeof(params)
kind    .byte
coords  .res 4
        END_PARAM_BLOCK
        .assert .sizeof(event_params) = .sizeof(MGTK::Event), error, "size mismatch"
        PARAM_BLOCK screentowindow_params, btk::command_data + .sizeof(params)
window_id       .byte
screen          .res 4
window          .res 4
        END_PARAM_BLOCK
        .assert screentowindow_params + .sizeof(screentowindow_params) <= $2F, error, "bounds"
        .assert screentowindow_params::screen = event_params::coords, error, "mismatch"

        ;; If disabled, return canceled
        bit     state
    IF_NS
        return  #$80
    END_IF

        jsr     _SetPort

        ;; Initial state
        copy    #0, down_flag

        ;; Do initial inversion
        jsr     _Invert

        ;; Event loop
loop:   MGTK_CALL MGTK::GetEvent, event_params
        lda     event_params::kind
        cmp     #MGTK::EventKind::button_up
        beq     exit
        lda     window_id
    IF_ZERO
        MGTK_CALL MGTK::MoveTo, event_params::coords
    ELSE
        sta     screentowindow_params::window_id
        MGTK_CALL MGTK::ScreenToWindow, screentowindow_params
        MGTK_CALL MGTK::MoveTo, screentowindow_params::window
    END_IF
        MGTK_CALL MGTK::InRect, rect
        cmp     #MGTK::inrect_inside
        beq     inside
        lda     down_flag       ; outside but was inside?
        beq     toggle
        bne     loop            ; always

inside: lda     down_flag       ; already depressed?
        beq     loop

toggle: jsr     _Invert
        lda     down_flag
        eor     #$80
        sta     down_flag
        jmp     loop

exit:   lda     down_flag       ; was depressed?
        bne     :+
        jsr     _Invert
:       lda     down_flag
        rts

        ;; --------------------------------------------------

down_flag:
        .byte   0


.endproc ; TrackImpl

.ifndef BTK_SHORT
;;; ============================================================

;;; Padding between radio/checkbox and label
kLabelPadding = 5

kRadioButtonWidth       = 15
kRadioButtonHeight      = 7

.params rb_params
        DEFINE_POINT viewloc, 0, 0
mapbits:        .addr   SELF_MODIFIED
mapwidth:       .byte   3
reserved:       .byte   0
        DEFINE_RECT maprect, 0, 0, kRadioButtonWidth, kRadioButtonHeight
        REF_MAPINFO_MEMBERS
.endparams

checked_rb_bitmap:
        PIXELS  "....########...."
        PIXELS  "..###......###.."
        PIXELS  "###...####...###"
        PIXELS  "##..########..##"
        PIXELS  "##..########..##"
        PIXELS  "###...####...###"
        PIXELS  "..###......###.."
        PIXELS  "....########...."

unchecked_rb_bitmap:
        PIXELS  "....########...."
        PIXELS  "..###......###.."
        PIXELS  "###..........###"
        PIXELS  "##............##"
        PIXELS  "##............##"
        PIXELS  "###..........###"
        PIXELS  "..###......###.."
        PIXELS  "....########...."

;;; ============================================================

.proc RadioDrawImpl
        PARAM_BLOCK params, btk::command_data
a_record  .addr
        END_PARAM_BLOCK
        .assert a_record = params::a_record, error, "a_record must be first"

        jsr     _SetPort

        ;; Initial size is just the button
        add16_8 rect+MGTK::Rect::x1, #kRadioButtonWidth, rect+MGTK::Rect::x2
        add16_8 rect+MGTK::Rect::y1, #kRadioButtonHeight, rect+MGTK::Rect::y2

        lda     a_label
        ora     a_label+1
    IF_NOT_ZERO
        ;; Draw the label
        pos := $B
        add16_8 rect+MGTK::Rect::x1, #kLabelPadding + kRadioButtonWidth, pos+MGTK::Point::xcoord
        add16_8 rect+MGTK::Rect::y1, #kSystemFontHeight - 1, pos+MGTK::Point::ycoord
        MGTK_CALL MGTK::MoveTo, pos
        jsr     _DrawLabel

        ;; And measure it for hit testing
        jsr     _MeasureLabel
        addax   rect+MGTK::Rect::x2
        add16_8 rect+MGTK::Rect::x2, #kLabelPadding
        add16_8 rect+MGTK::Rect::y2, #kSystemFontHeight - kRadioButtonHeight
    END_IF

        jsr     _MaybeDrawAndMeasureShortcut
        jsr     _WriteRectBackToButtonRecord

        jmp     _DrawRadioBitmap
.endproc ; RadioDrawImpl

;;; ============================================================

.proc RadioUpdateImpl
        PARAM_BLOCK params, btk::command_data
a_record  .addr
        END_PARAM_BLOCK
        .assert a_record = params::a_record, error, "a_record must be first"

        jsr     _SetPort

        FALL_THROUGH_TO _DrawRadioBitmap
.endproc ; RadioUpdateImpl

.proc _DrawRadioBitmap
        COPY_STRUCT MGTK::Point, rect+MGTK::Rect::topleft, rb_params::viewloc
        ldax    #unchecked_rb_bitmap
        bit     state
    IF_NS
        ldax    #checked_rb_bitmap
    END_IF
        stax    rb_params::mapbits

        MGTK_CALL MGTK::SetPenMode, notpencopy
        MGTK_CALL MGTK::PaintBitsHC, rb_params
        rts
.endproc ; _DrawRadioBitmap

;;; ============================================================

kCheckboxWidth       = 17
kCheckboxHeight      = 8

.params cb_params
        DEFINE_POINT viewloc, 0, 0
mapbits:        .addr   SELF_MODIFIED
mapwidth:       .byte   3
reserved:       .byte   0
        DEFINE_RECT maprect, 0, 0, kCheckboxWidth, kCheckboxHeight
        REF_MAPINFO_MEMBERS
.endparams

checked_cb_bitmap:
        PIXELS  "##################"
        PIXELS  "####..........####"
        PIXELS  "##..##......##..##"
        PIXELS  "##....##..##....##"
        PIXELS  "##......##......##"
        PIXELS  "##....##..##....##"
        PIXELS  "##..##......##..##"
        PIXELS  "####..........####"
        PIXELS  "##################"

unchecked_cb_bitmap:
        PIXELS  "##################"
        PIXELS  "##..............##"
        PIXELS  "##..............##"
        PIXELS  "##..............##"
        PIXELS  "##..............##"
        PIXELS  "##..............##"
        PIXELS  "##..............##"
        PIXELS  "##..............##"
        PIXELS  "##################"

;;; ============================================================

.proc CheckboxDrawImpl
        PARAM_BLOCK params, btk::command_data
a_record  .addr
        END_PARAM_BLOCK
        .assert a_record = params::a_record, error, "a_record must be first"

        jsr     _SetPort

        ;; Initial size is just the button
        add16_8 rect+MGTK::Rect::x1, #kCheckboxWidth, rect+MGTK::Rect::x2
        add16_8 rect+MGTK::Rect::y1, #kCheckboxHeight, rect+MGTK::Rect::y2

        lda     a_label
        ora     a_label+1
    IF_NOT_ZERO
        ;; Draw the label
        pos := $B
        add16_8 rect+MGTK::Rect::x1, #kLabelPadding + kCheckboxWidth, pos+MGTK::Point::xcoord
        add16_8 rect+MGTK::Rect::y1, #kSystemFontHeight, pos+MGTK::Point::ycoord
        MGTK_CALL MGTK::MoveTo, pos
        jsr     _DrawLabel

        ;; And measure it for hit testing
        jsr     _MeasureLabel
        addax   rect+MGTK::Rect::x2
        add16_8 rect+MGTK::Rect::x2, #kLabelPadding
        add16_8 rect+MGTK::Rect::y2, #kSystemFontHeight - kCheckboxHeight
    END_IF

        jsr     _MaybeDrawAndMeasureShortcut
        jsr     _WriteRectBackToButtonRecord

        jmp     _DrawCheckboxBitmap
.endproc ; CheckboxDrawImpl

;;; ============================================================

.proc CheckboxUpdateImpl
        PARAM_BLOCK params, btk::command_data
a_record  .addr
        END_PARAM_BLOCK
        .assert a_record = params::a_record, error, "a_record must be first"

        jsr     _SetPort

        FALL_THROUGH_TO _DrawCheckboxBitmap
.endproc ; CheckboxUpdateImpl

.proc _DrawCheckboxBitmap
        COPY_STRUCT MGTK::Point, rect+MGTK::Rect::topleft, cb_params::viewloc
        ldax    #unchecked_cb_bitmap
        bit     state
    IF_NS
        ldax    #checked_cb_bitmap
    END_IF
        stax    cb_params::mapbits

        MGTK_CALL MGTK::SetPenMode, notpencopy
        MGTK_CALL MGTK::PaintBitsHC, cb_params
        rts
.endproc ; _DrawCheckboxBitmap

;;; ============================================================

;;; If option is enabled, and if `a_shortcut` is not null,
;;; draw it and add the width to `rect`.
.proc _MaybeDrawAndMeasureShortcut
        ldx     #DeskTopSettings::options
        jsr     ReadSetting
        and     #DeskTopSettings::kOptionsShowShortcuts
    IF_NOT_ZERO
        lda     a_shortcut
        ora     a_shortcut+1
      IF_NOT_ZERO
        jsr     _DrawShortcut

        jsr     _MeasureShortcut
        addax   rect+MGTK::Rect::x2
      END_IF
    END_IF

        rts
.endproc ; _MaybeDrawAndMeasureShortcut

;;; Copies `rect` back into `a_record`
.proc _WriteRectBackToButtonRecord
        ;; Write rect back to button record
        ldx     #.sizeof(MGTK::Rect)-1
        ldy     #BTK::ButtonRecord::rect + .sizeof(MGTK::Rect)-1
:       lda     rect,x
        sta     (a_record),y
        dey
        dex
        bpl     :-
        rts
.endproc ; _WriteRectBackToButtonRecord

;;; ============================================================
.endif ; BTK_SHORT

.endscope
