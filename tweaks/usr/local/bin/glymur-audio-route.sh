#!/bin/bash
# Establish the glymur AudioReach FE<->BE + WSA speaker + VA mic route at boot.
C=""
for i in $(seq 1 90); do
  C=$(cat /proc/asound/cards 2>/dev/null | grep -oE '^ *[0-9]+ \[GLYMUR' | grep -oE '[0-9]+' | head -1)
  [ -n "$C" ] && amixer -c "$C" cget name='WSA_CODEC_DMA_RX_0 Audio Mixer MultiMedia2' >/dev/null 2>&1 && break
  sleep 1
done
[ -z "$C" ] && exit 0
cs(){ amixer -c "$C" cset name="$1" "$2" >/dev/null 2>&1; }
# FE->BE routes
cs 'WSA_CODEC_DMA_RX_0 Audio Mixer MultiMedia2' 1
cs 'MultiMedia4 Mixer VA_CODEC_DMA_TX_0' 1
# WSA + WSA2 macro
for M in WSA WSA2; do
  cs "$M WSA RX0 MUX" AIF1_PB; cs "$M WSA RX1 MUX" AIF1_PB
  cs "$M WSA_RX0 INP0" RX0; cs "$M WSA_RX1 INP0" RX1
  cs "$M WSA_COMP1 Switch" 1; cs "$M WSA_COMP2 Switch" 1
  cs "$M WSA_RX0 Digital Volume" 81; cs "$M WSA_RX1 Digital Volume" 77
done
# WSA8845 speakers
for S in WooferLeft TweeterLeft WooferRight TweeterRight; do
  cs "$S COMP Switch" 1; cs "$S BOOST Switch" 1; cs "$S DAC Switch" 1
  cs "$S PBR Switch" 1; cs "$S WSA MODE" 0; cs "$S PA Volume" 6
done
# VA DMIC capture
cs 'VA DEC0 MUX' VA_DMIC; cs 'VA DMIC MUX0' DMIC0; cs 'VA_AIF1_CAP Mixer DEC0' 1; cs 'VA_DEC0 Volume' 100
cs 'VA DEC1 MUX' VA_DMIC; cs 'VA DMIC MUX1' DMIC1; cs 'VA_AIF1_CAP Mixer DEC1' 1; cs 'VA_DEC1 Volume' 100
exit 0
