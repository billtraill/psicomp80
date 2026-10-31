make DEBUG=1 SYMBOLS=1 OPTIMIZE=0 \
  SOURCES=src/mame/drivers/psicomp80.cpp \
  OSD=sdl \
  USE_LIBSDL=1 \
  SDL_INSTALL_ROOT=/opt/homebrew \
  -j$(sysctl -n hw.ncpu)
