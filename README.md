= Nabu Digital Rain

![Digital Rain Animated Gif](/Images/rain.gif?raw=true)

A Digital Rain / Matrix demo for the Nabu PC

== Features / Keys
* `c`     -- Toggle chonky or thin font
* `+`/`-` -- Speed up or slow down the update speed
* `r`     -- Reset/clear the screen
* `Pause` -- Pause

Available as a homebrew .nabu or a CP/M .com.

If you have the hardware the F18A builds set a custom colour palette making the dark green darker and replacing white with a very bright green.  This isn't currently supported by emulators so you'll need real hardware to see it.

== Building

Assemble with [sjasmplus](https://github.com/z00m128/sjasmplus).

```
    sjasmplus --syntax=ab DigiRain.asm --lst=DigiRain.lst --raw=DigiRain.nabu
```

`-DCPM` will build a CP/M .com file.  `-DF18A` will build with F18A custom colour support.

== Additional Credits and Thanks

The random function is originally from [Aleksi Eeben's](http://www.cncd.fi/aeeben) 1K WHACK for the VIC20.  The z80 version used here is from [Deep Dungeon Adventure](https://github.com/artrag/Deep-Dungeon-Adventure) by ARTRAG, John Hassink and Huey of Trilobyte.  See random.asm for license information.

The fonts are derived from emutyworks [8x8DotJPFont](https://github.com/emutyworks/8x8DotJPFont), which itself is derived from Num Kadoma's [Misaki font](http://littlelimit.net/misaki.htm).  See the font files for license information.

Thanks to the Nabu PC Discord community.  Particularly c1ph3rpunk for the inspirtation and showing this at VCFMW, Licca for sharing code and answering random questions, Matthew for creating the F18A and answering questions on how to program it, GryBsh for NNS, and productiondave for troubleshooting and finding the fix for a random video glitch. (Turns out the 16k dram refresh VDP setting is important on the Nabu!)

