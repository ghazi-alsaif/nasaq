import QtQuick

// Wrap any NASAQ surface in Rtl { … } to mirror its layout when the UI
// language is right-to-left (Arabic). Text alignment follows automatically.
Item {
  LayoutMirroring.enabled: Tr.rtl
  LayoutMirroring.childrenInherit: true
}
