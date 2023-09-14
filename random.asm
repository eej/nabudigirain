; Random function, originally from Aleksi Eeben's 1K WHACK
; http://www.cncd.fi/aeeben
; z80 version from Deep Dungeon Adventure by ARTRAG, John Hassink and Huey of Trilobyte
; https://github.com/artrag/Deep-Dungeon-Adventure
;
; https://www.msx.org/news/development/en/deep-dungeon-adventure-source-code
; "The distributed DDA files are freeware. If ever you could put one or more of these files to good use in your own projects, 
; don't forget to credit the original creators; ARTRAG, John Hassink and Huey of Trilobyte."

random:
        inc (ix+seed2)
        ld a,(ix+seed2)
        add a,(ix+seed1)
        adc a,(ix+seed2)
        ld (ix+seed1),a
        push af
        xor (ix+seed2)
        ld (ix+seed2),a
        pop af
        ld a,(ix+seed2)
        scf
        sbc (ix+prevr)
        ld (ix+prevr),a
        and a
        ;; Debug HACK
        ;ld a, 6
        ret

randvars ds 3
seed1 = 0
seed2 = 1
prevr = 2