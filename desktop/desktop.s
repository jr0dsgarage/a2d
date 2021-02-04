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
;;; DeskTop - the actual application
;;; ============================================================

        .include "internal.inc"

        .include "loader.s"

        .include "aux.s"
        .include "lc.s"
        .include "res.s"
        .include "main.s"

        .include "init.s"

        .include "invoker.s"

;;; ============================================================
;;; Disk Copy Overlays

.scope disk_copy
        .include "disk_copy1.s"
        .include "disk_copy2.s"
        .include "disk_copy3.s"
        .include "disk_copy4.s"
.endscope

;;; ============================================================
;;; Other Overlays

.macro jump_table_entry addr
        .byte 0
        .addr addr
.endmacro

        .include "ovl_format_erase.s"
        .include "ovl_selector_pick.s" ; Selector (1/2) @ $9000-$9FFF
        .include "ovl_file_dialog.s"   ; File Dialog    @ $5000-$6FFF
        .include "ovl_file_copy.s"     ; File Copy      @ $7000-$77FF
        .include "ovl_file_delete.s"   ; File Delete    @ $7000-$77FF
        .include "ovl_selector_edit.s" ; Selector (2/2) @ $7000-$77FF

        common_overlay_L5000 := file_dialog::L5000
