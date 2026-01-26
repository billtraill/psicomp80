Done — I generated a new `psicomp80.cpp` that:

* Implements a **2513-style character generator** (64 chars × 8 rows × 5 bits)
* Uses **VRAM bits 0–5** as the 6-bit character index
* Uses **VRAM bit 6** to select **ASCII font vs graphics font**
* Includes a **base “2513-like” ASCII set** (approximate, but readable: space, punctuation, digits, A–Z, etc. for codes **0x20–0x5F**)
* Includes a **placeholder graphics font table** (`gfx_font_64x8x5`) that you can populate by hand later
* Keeps the **NMI on keypress** + **IRQ0 data-ready** model from the earlier driver
* Renders characters as **5 pixels + 1 spacer** wide and **8 rows + 2 blank** high (6×10 cell)

**Download:** [psicomp80_with_2513_font.cpp](sandbox:/mnt/data/psicomp80_with_2513_font.cpp)

### Where to put your graphics characters later

In the file, look for:

```cpp
std::array<std::array<u8, 8>, 64> psicomp80_state::gfx_font_64x8x5 = ...
```

Each entry is **8 rows**, each row is a **5-bit pattern** in bits **0..4** (I render bit4 as leftmost pixel).

If you want, once you upload the scans of the graphics EPROM (image or hex), I can decode them into that exact table automatically.
