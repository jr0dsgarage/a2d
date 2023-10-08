;;; ============================================================
;;; Overlay for Selector Edit - drives File Picker dialog
;;;
;;; Compiled as part of desktop.s
;;; ============================================================

        BEGINSEG OverlayShortcutEdit


;;; Constants specific to this dialog and used by the caller. These
;;; correspond to properties of `docs/Selector_List_Format.md` but are
;;; specific to this dialog and the caller.

kRunListPrimary   = 1           ; entry is in first 8 (menu and dialog)
kRunListSecondary = 2           ; entry is in second 16 (dialog only)

kCopyOnBoot = 1                 ; corresponds to `kSelectorEntryCopyOnBoot`
kCopyOnUse  = 2                 ; corresponds to `kSelectorEntryCopyOnUse`
kCopyNever  = 3                 ; corresponds to `kSelectorEntryCopyNever`

.scope SelectorEditOverlay

        MGTKEntry := MGTKRelayImpl
        BTKEntry := BTKRelayImpl

.proc Run
        ;; A = (obsolete, was dialog type)
        ;; Y = is_add_flag | copy_when
        ;; X = which_run_list
        stx     which_run_list
        sty     is_add_flag
        tya
        and     #$7F
        sta     copy_when

        tsx
        stx     saved_stack

        jsr     file_dialog::Init
        copy    #$80, file_dialog::extra_controls_flag

        ldax    #label_edit
        bit     is_add_flag
    IF_NS
        ldax    #label_add
    END_IF
        jsr     file_dialog::OpenWindow
        jsr     DrawControls

        COPY_BYTES file_dialog::kJumpTableSize, jt_callbacks, file_dialog::jump_table

        jsr     file_dialog::SetPortForDialog
        lda     which_run_list
        sec
        jsr     UpdateRunListButton
        lda     copy_when
        sec
        jsr     DrawCopyWhenButton

        copy16  #HandleClick, file_dialog::click_handler_hook
        copy16  #HandleKey, file_dialog::key_handler_hook
        copy    #kSelectorMaxNameLength, file_dialog_res::line_edit::max_length

        ;; If we were passed a path (`path_buf0`), prep the file dialog with it.
        lda     path_buf0
    IF_ZERO
        jsr     file_dialog::InitPathWithDefaultDevice
    ELSE
        COPY_STRING path_buf0, file_dialog::path_buf

        ;; Was it just a volume name, e.g. "/VOL"?
        jsr     IsVolPath
      IF_CS
        ;; No, strip to parent directory
        param_call main::RemovePathSegment, file_dialog::path_buf

        ;; And populate `buffer` with filename
        ldx     file_dialog::path_buf
        inx
        ldy     #0
:       inx
        iny
        lda     path_buf0,x
        sta     buffer,y
        cpx     path_buf0
        bne     :-
        sty     buffer
      END_IF
    END_IF
        param_call file_dialog::UpdateListFromPathAndSelectFile, buffer
        jmp     file_dialog::EventLoop

buffer: .res 16, 0

.endproc ; Init

;;; ============================================================

.proc DrawControls
        jsr     file_dialog::SetPortForDialog
        param_call file_dialog::DrawLineEditLabel, enter_the_name_to_appear_label

        MGTK_CALL MGTK::MoveTo, add_a_new_entry_to_label_pos
        param_call main::DrawString, add_a_new_entry_to_label_str

        BTK_CALL BTK::RadioDraw, primary_run_list_params
        BTK_CALL BTK::RadioDraw, secondary_run_list_params

        MGTK_CALL MGTK::MoveTo, down_load_label_pos
        param_call main::DrawString, down_load_label_str

        BTK_CALL BTK::RadioDraw, at_first_boot_params
        BTK_CALL BTK::RadioDraw, at_first_use_params
        BTK_CALL BTK::RadioDraw, never_params

        rts
.endproc ; DrawControls

;;; ============================================================

saved_stack:
        .byte   0

jt_callbacks:
        jmp     HandleOK
        jmp     HandleCancel
        .assert * - jt_callbacks = file_dialog::kJumpTableSize, error, "Table size error"

;;; ============================================================
;;; Close window and finish (via saved_stack) if OK
;;; Outputs: A = 0 if OK
;;;          X = which run list (1=primary, 2=secondary)
;;;          Y = copy when (1=boot, 2=use, 3=never)

.proc HandleOK
        param_call file_dialog::GetPath, path_buf0

        ;; If name is empty, use last path segment
        lda     text_input_buf
    IF_ZERO
        ldx     path_buf0
:       lda     path_buf0,x
        cmp     #'/'
        beq     :+
        dex
        bne     :-              ; always, since path is valid
:       inx

        ldy     #1
:       lda     path_buf0,x
        sta     text_input_buf,y
        cpx     path_buf0
        beq     :+
        inx
        iny
        bne     :-              ; always

:
        ;; Truncate if necessary
        cpy     #kSelectorMaxNameLength+1
        bcc     :+
        ldy     #kSelectorMaxNameLength
:       sty     text_input_buf
    END_IF

        jsr     IsVolPath
        bcs     ok              ; nope
        lda     copy_when       ; Disallow copying volume to ramcard
        cmp     #kCopyNever
        beq     ok
        FALL_THROUGH_TO invalid

invalid:
        lda     #ERR_INVALID_PATHNAME
        jmp     ShowAlert

ok:     jsr     file_dialog::CloseWindow
        copy16  #file_dialog::NoOp, file_dialog::key_handler_hook+1
        ldx     saved_stack
        txs
        ldx     which_run_list
        ldy     copy_when
        return  #0
.endproc ; HandleOK

;;; Returns C=0 if `path_buf0` is a volume path, C=1 otherwise
;;; Assert: Path is valid
.proc IsVolPath
        ldy     path_buf0
:       lda     path_buf0,y
        cmp     #'/'
        beq     found
        dey
        bne     :-

found:  cpy     #2
        rts
.endproc ; IsVolPath

;;; ============================================================

.proc HandleCancel
        jsr     file_dialog::CloseWindow
        copy16  #file_dialog::NoOp, file_dialog::key_handler_hook+1
        ldx     saved_stack
        txs
        return  #$FF
.endproc ; HandleCancel

;;; ============================================================

which_run_list:
        .byte   0
copy_when:
        .byte   0
is_add_flag:                    ; high bit set = Add, clear = Edit
        .byte   0

;;; ============================================================

.proc HandleClick
        MGTK_CALL MGTK::InRect, primary_run_list_rec::rect
        cmp     #MGTK::inrect_inside
        jeq     ClickPrimaryRunListCtrl

        MGTK_CALL MGTK::InRect, secondary_run_list_rec::rect
        cmp     #MGTK::inrect_inside
        jeq     ClickSecondaryRunListCtrl

        MGTK_CALL MGTK::InRect, at_first_boot_rec::rect
        cmp     #MGTK::inrect_inside
        jeq     ClickAtFirstBootCtrl

        MGTK_CALL MGTK::InRect, at_first_use_rec::rect
        cmp     #MGTK::inrect_inside
        jeq     ClickAtFirstUseCtrl

        MGTK_CALL MGTK::InRect, never_rec::rect
        cmp     #MGTK::inrect_inside
        jeq     ClickNeverCtrl

        return  #0
.endproc ; HandleClick

.proc ClickPrimaryRunListCtrl
        lda     which_run_list
        cmp     #kRunListPrimary
        beq     :+
        clc
        jsr     UpdateRunListButton
        lda     #kRunListPrimary
        sta     which_run_list
        sec
        jsr     UpdateRunListButton
:       return  #$FF
.endproc ; ClickPrimaryRunListCtrl

.proc ClickSecondaryRunListCtrl
        lda     which_run_list
        cmp     #kRunListSecondary
        beq     :+
        clc
        jsr     UpdateRunListButton
        lda     #kRunListSecondary
        sta     which_run_list
        sec
        jsr     UpdateRunListButton
:       return  #$FF
.endproc ; ClickSecondaryRunListCtrl

.proc ClickAtFirstBootCtrl
        lda     copy_when
        cmp     #kCopyOnBoot
        beq     :+
        clc
        jsr     DrawCopyWhenButton
        lda     #kCopyOnBoot
        sta     copy_when
        sec
        jsr     DrawCopyWhenButton
:       return  #$FF
.endproc ; ClickAtFirstBootCtrl

.proc ClickAtFirstUseCtrl
        lda     copy_when
        cmp     #kCopyOnUse
        beq     :+
        clc
        jsr     DrawCopyWhenButton
        lda     #kCopyOnUse
        sta     copy_when
        sec
        jsr     DrawCopyWhenButton
:       return  #$FF
.endproc ; ClickAtFirstUseCtrl

.proc ClickNeverCtrl
        lda     copy_when
        cmp     #kCopyNever
        beq     :+
        clc
        jsr     DrawCopyWhenButton
        lda     #kCopyNever
        sta     copy_when
        sec
        jsr     DrawCopyWhenButton
:       return  #$FF
.endproc ; ClickNeverCtrl

;;; ============================================================

.proc UpdateRunListButton
        ldx     #0
        bcc     :+
        ldx     #$80
:
        cmp     #kRunListPrimary
    IF_EQ
        stx     primary_run_list_rec::state
        BTK_CALL BTK::RadioUpdate, primary_run_list_params
    ELSE
        stx     secondary_run_list_rec::state
        BTK_CALL BTK::RadioUpdate, secondary_run_list_params
    END_IF

        rts
.endproc ; UpdateRunListButton

.proc DrawCopyWhenButton
        ldx     #0
        bcc     :+
        ldx     #$80
:
        cmp     #kCopyOnBoot
        bne     :+
        stx     at_first_boot_rec::state
        BTK_CALL BTK::RadioUpdate, at_first_boot_params
        rts
:
        cmp     #kCopyOnUse
        bne     :+
        stx     at_first_use_rec::state
        BTK_CALL BTK::RadioUpdate, at_first_use_params
        rts
:
        stx     never_rec::state
        BTK_CALL BTK::RadioUpdate, never_params
        rts
.endproc ; DrawCopyWhenButton

;;; ============================================================

.proc HandleKey
        jsr     file_dialog::SetPortForDialog
        lda     event_params::modifiers
        RTS_IF_ZERO

        lda     event_params::key
        cmp     #'1'
        jeq     ClickPrimaryRunListCtrl

        cmp     #'2'
        jeq     ClickSecondaryRunListCtrl

        cmp     #'3'
        jeq     ClickAtFirstBootCtrl

        cmp     #'4'
        jeq     ClickAtFirstUseCtrl

        cmp     #'5'
        jeq     ClickNeverCtrl

        rts
.endproc ; HandleKey

;;; ============================================================

.endscope ; SelectorEditOverlay
SelectorEditOverlay__Run := SelectorEditOverlay::Run

        ENDSEG OverlayShortcutEdit
