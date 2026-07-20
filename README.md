# Nays2DH

## Dynamic vegetation extension

This fork keeps the upstream Nays2DH flow, sediment-transport, bed-evolution,
and bank-erosion equations. The added coupling is **body drag only**. There is
**no root-induced sediment reduction**: root depth is used only to decide
whether cumulative local scour uproots a plant.

At each vegetation update, effective age is defined exactly as:

`effective age = actual age * growth multiplier`

Effective age is limited by a configurable 30-year cap before the willow
allometry is evaluated:

- stem density: `N = 1.52 Y^-0.63` (trees per square metre)
- stem diameter: `D = 0.11 Y^1.77` (centimetres)
- height: `H = 1.27 D^0.79` (metres)
- root depth: `Hr = 28.9 D^0.23 / 100` (metres)
- projected density used by drag: `lambda = N * D / 100` (inverse metres)
- Nays2DH vegetation coefficient: `cd_veg = 0.5 * c_tree * lambda`

The default flood cycle is 25 h. During a cycle, the solver records maximum
scour below each plant's cycle-start bed elevation and removes the plant when
that scour exceeds its allometric root depth. At the cycle boundary, surviving
plants gain one year of actual age and bare cells recruit at age 1 only where
water depth is at most 0.05 m. A growth multiplier of 2 therefore gives a
2-year effective age to an actual 1-year plant; it does not advance the flood
clock or add two years per cycle.

For the requested quick experiment, use 32 flood cycles (800 h total with the
25 h default) and `veg_growth_multiplier = 2`. The model is intentionally a
physics-focused reproduction rather than a calibrated ecological forecast.

### iRIC controls and outputs

Enable `Dynamic vegetation` in its calculation-condition tab. The original
static vegetation behavior remains available when it is disabled. Dynamic
cell outputs are presence, actual age, effective age, projected density,
height, root depth, and maximum scour since the last cycle boundary. Bed
elevation remains the native Nays2DH result, so iRIC can directly compare
terrain and vegetation fields without a separate plotting format.

### Cloud build and installation

Run the `build-dynamic-vegetation-solver` workflow. Download the GitHub Actions artifact
named `iRICsolvers_v4_Nays2DH_Vegetation`. Extract that folder
under the iRIC `solvers` directory. On this machine the intended path is:

`C:\Users\ASUS\iRIC_v4\solvers\iRICsolvers_v4_Nays2DH_Vegetation`

Keep `iRICsolvers_v4_Nays2DH` beside it; do not overwrite the stock solver.
The artifact contains the unique solver definition, executable, translations,
and the Intel runtime DLLs detected from the compiled executable.

The workflow deliberately uses Intel Classic Fortran `ifort` 2024.2, matching
the compiler family used by upstream Nays2DH. An A/B smoke test showed that an
otherwise unmodified upstream solver built with `ifx` 2026.1 overflowed in
`HCAL` on its first time step, while the stock `ifort` build advanced normally.
The vegetation equations were therefore not the cause of that failure.

Current limitation: vegetation state is not included in Nays2DH hot-start
files, so a 32-cycle vegetation experiment should be run continuously.

iRICに登載されている平面二次元河床変動ソルバーNays2DHのリポジトリです．

## 動作環境

iRICに同封されているものは，Intel Open APIを使ってコンパイルをしています．

同環境で使用したい場合は例えば下記のページなどで環境構築をお願いします．

https://qiita.com/Kazutake/items/a069f86d21ca43b6c153

## 改良版をiRICで動かす

srcフォルダにあるmake.batでコンパイルできます．もちろん，そのほかの方法でコンパイルいただいても大丈夫だと思います．

installフォルダにNays2DH.exeが生成されますので，iRICのインストールフォルダにある，solvers/iRICsolvers_v4_Nays2DHにコピーすると更新ソルバーが使えます．

条件設定ファイルdefinition.xmlを変更した際も同様です．

もし改良版をオリジナルと分けたい場合は，別途フォルダを作成し，そこにNays2DH.exe，definition.xmlなどをコピーしてください．その際，definition.xml内にあるcaptionなどを変更しておくと，区別がつきやすいです．
