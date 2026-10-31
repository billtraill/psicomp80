# Building MAME for psicomp80 Development

This guide covers building a debug-enabled version of MAME specifically for developing and debugging the `psicomp80` driver.

## Prerequisites

### macOS Requirements

1. **Xcode Command Line Tools**
   ```bash
   xcode-select --install
   ```

2. **Homebrew** (if not already installed)
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

3. **SDL2 via Homebrew**
   
   Install SDL2 using Homebrew:
   ```bash
   brew install sdl2
   ```
   
   This installs SDL2 to `/opt/homebrew` (on Apple Silicon) or `/usr/local` (on Intel Macs).
   
   **Note:** The system-installed SDL2 framework may have permission issues. Using Homebrew's version avoids these problems.

## Build Instructions

### Step 1: Regenerate Project Files

First, regenerate the build system with the correct SDL2 configuration. **Do not use `SOURCES=` at this step:**

```bash
cd ~/localdev/mame
make DEBUG=1 SYMBOLS=1 OPTIMIZE=0 \
  OSD=sdl \
  USE_LIBSDL=1 \
  SDL_INSTALL_ROOT=/opt/homebrew \
  REGENIE=1
```

**Note:** On Intel Macs, use `SDL_INSTALL_ROOT=/usr/local` instead.

This step:
- Regenerates all project files with SDL2 library linking (not framework)
- Configures the build to use Homebrew's SDL2 installation
- Takes a few minutes to complete

### Step 2: Add Driver to mame.lst (if not already present)

The driver must be listed in `src/mame/mame.lst` to be included in the build. Check if it's already there:

```bash
grep -i "psicomp80" src/mame/mame.lst
```

If not found, add it to `src/mame/mame.lst`. Find an appropriate location (alphabetically) and add:

```
@source:drivers/psicomp80.cpp
psicomp80
```

For example, it can be added before the `@source:psikyo/` entries around line 40003.

### Step 3: Build with psicomp80 Driver

After regeneration and adding to mame.lst, build with only the `psicomp80` driver:

```bash
make DEBUG=1 SYMBOLS=1 OPTIMIZE=0 \
  SOURCES=src/mame/drivers/psicomp80.cpp \
  OSD=sdl \
  USE_LIBSDL=1 \
  SDL_INSTALL_ROOT=/opt/homebrew \
  -j$(sysctl -n hw.ncpu)
```

**Build Options Explained:**
- `DEBUG=1`: Enables runtime assertions and additional diagnostics
- `SYMBOLS=1`: Includes debugging symbols for gdb/lldb
- `OPTIMIZE=0`: Disables optimization for easier debugging
- `SOURCES=src/mame/drivers/psicomp80.cpp`: Builds only this driver and its dependencies
- `OSD=sdl`: Uses SDL for output/input
- `USE_LIBSDL=1`: Links against SDL2 library (not framework)
- `SDL_INSTALL_ROOT=/opt/homebrew`: Points to Homebrew installation
- `-j$(sysctl -n hw.ncpu)`: Parallel compilation using all CPU cores

**Important:** Do not use `REGENIE=1` with `SOURCES=` - they conflict. Only regenerate when changing SDL configuration.

### Step 4: Verify Build

The binary will be created at:
```
./mamed
```

Test that it runs:
```bash
./mamed -help
```

You should see MAME's help output without SDL framework errors.

## Verifying the Driver is Included

After building, verify the driver is recognized:

```bash
./mamed -listxml psicomp80 | head -5
```

You should see XML output. If you get "Unknown system", the driver wasn't included in the build - check that it's in `mame.lst` and rebuild.

## Running psicomp80

### ROM File Setup

1. **Create ROMs directory structure:**
   ```bash
   mkdir -p roms/psicomp80
   ```

2. **Place your ROM file:**
   - MAME expects ROM files in a subdirectory named after the machine
   - Copy your ROM file to `roms/psicomp80/psicomp80.rom`
   - The ROM filename must match what's defined in the driver (check with `-listxml`)
   - The ROM must match the expected CRC and SHA1 checksums

3. **Check expected ROM files and checksums:**
   ```bash
   ./mamed -listxml psicomp80 | grep -A 5 "rom name"
   ```
   
   This will show:
   - ROM filename: `psicomp80.rom`
   - Size: `3072` bytes (0x0c00)
   - CRC: `ea151b9a`
   - SHA1: `40bea1058ad79f1ca47aec7151c9749cba1843d9`

4. **Verify your ROM file matches:**
   ```bash
   # Check SHA1 (should match the expected value)
   shasum -a 1 roms/psicomp80/psicomp80.rom
   
   # Check file size (should be 3072 bytes)
   ls -lh roms/psicomp80/psicomp80.rom
   ```

**Important:** MAME looks for ROMs in `roms/<machine_name>/` subdirectories, not directly in `roms/`. The error message "tried in psicomp80" indicates it's looking in the `roms/psicomp80/` directory.

### Running the Emulator

**Basic run:**
```bash
./mamed psicomp80
```

**With debugger enabled:**
```bash
./mamed psicomp80 -debug
```
- Press `~` (tilde) during emulation to break into the debugger
- The debugger will also break after initial soft reset on startup

**With custom ROM path:**
```bash
./mamed psicomp80 -rompath /path/to/your/roms -debug
```

**With logging:**
```bash
./mamed psicomp80 -debug -log
```
- Creates `error.log` with internal log messages

## Debugging

### Using MAME's Built-in Debugger

1. Run with `-debug` flag
2. Press `~` to break into debugger
3. Use debugger commands:
   - `help` - List all commands
   - `g` - Go/continue execution
   - `s` - Step instruction
   - `r` - Show registers
   - `m <address>` - View memory
   - `bpset <address>` - Set breakpoint

### Using macOS Cocoa Debugger

On macOS, MAME includes a native Cocoa debugger (default). Run with:
```bash
./mamed psicomp80 -debug -debugger osx
```

### Using Qt Debugger (Linux/Windows)

The Qt debugger provides a GUI interface but **is not easily available on macOS** when using Homebrew Qt installations, as MAME expects Qt frameworks rather than regular libraries.

To build with Qt debugger on macOS, you would need:
- Qt installed as frameworks (not via Homebrew)
- Or modify the build system to support Homebrew's library-based Qt installation

For macOS development, the built-in debugger or Cocoa debugger are recommended.

### Using lldb (macOS)

Attach lldb to the running process:
```bash
lldb ./mamed -- psicomp80 -debug
```

Or run and attach:
```bash
./mamed psicomp80 -debug &
lldb -p $!
```

In lldb:
- `b psicomp80_state::function_name` - Set breakpoint in driver code
- `b src/mame/drivers/psicomp80.cpp:123` - Set breakpoint at specific line
- `c` - Continue
- `n` - Next line
- `s` - Step into
- `p variable_name` - Print variable

## Incremental Rebuilds

After editing `src/mame/drivers/psicomp80.cpp`, rebuild with:

```bash
make DEBUG=1 SYMBOLS=1 OPTIMIZE=0 \
  SOURCES=src/mame/drivers/psicomp80.cpp \
  OSD=sdl \
  USE_LIBSDL=1 \
  SDL_INSTALL_ROOT=/opt/homebrew \
  -j$(sysctl -n hw.ncpu)
```

The build system will only recompile changed files.

## Troubleshooting

### SDL2 Framework Not Found Error

If you see:
```
dyld: Library not loaded: @rpath/SDL2.framework/Versions/A/SDL2
```

**Solution:**
1. Ensure SDL2 is installed via Homebrew: `brew install sdl2`
2. Regenerate project files with `REGENIE=1` (Step 1 above)
3. Verify `SDL_INSTALL_ROOT` matches your Homebrew path:
   - Apple Silicon: `/opt/homebrew`
   - Intel: `/usr/local`

### "None of the specified source files contain system drivers"

This happens when using `REGENIE=1` with `SOURCES=`. 

**Solution:** Regenerate without `SOURCES=` first (Step 1), then build with `SOURCES=` (Step 2).

### Build Takes Too Long

The `SOURCES=` option still builds many dependencies. For faster iteration:
- Only rebuild after making changes: `make ...` (without cleaning)
- Use `-j1` for single-threaded builds (easier to see errors)
- Consider building full MAME once, then use incremental builds

## Machine Information

- **Machine name:** `psicomp80`
- **Driver file:** `src/mame/drivers/psicomp80.cpp`
- **Status:** `MACHINE_NOT_WORKING | MACHINE_NO_SOUND` (work in progress)

## Additional Resources

- [MAME Compiling Guide](http://docs.mamedev.org/initialsetup/compilingmame.html)
- [MAME Debugger Documentation](http://docs.mamedev.org/debugger/index.html)
- [MAME Forums](https://forums.bannister.org/ubbthreads.php?ubb=cfrm&c=5)
