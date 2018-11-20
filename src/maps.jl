abstract type MAPPlot <: ESDLPlot end
import Colors: Color
import ESDL.Cubes: cubeproperties

mutable struct MAPPlotRGB <: MAPPlot
  xaxis
  yaxis
  rgbaxis
  dmin
  dmax
  c_1
  c_2
  c_3
  misscol::Color
  oceancol::Color
  cType
end
plotAxVars(p::MAPPlotRGB)=[
  FixedAx(p.xaxis,"X Axis",true,false,1),
  FixedAx(p.yaxis,"Y Axis",true,false,2),
  FixedAx(p.rgbaxis,"RGB Axis", true, true,-1),
  FixedVar(p.rgbaxis,p.c_1,channel_names(p.cType)[1],true),
  FixedVar(p.rgbaxis,p.c_2,channel_names(p.cType)[2],true),
  FixedVar(p.rgbaxis,p.c_3,channel_names(p.cType)[3],true)
  ]
function plotCall(p::MAPPlotRGB, d::AbstractCubeData, ixaxis, iyaxis, irgbaxis, c1,c2,c3,otherinds...)

  axlist = caxes(d)
  inds1 = ntuple(  i->(i==irgbaxis) ? axVal2Index(axlist[i],c1)  : in(i,(ixaxis,iyaxis)) ? (:) : axVal2Index(axlist[i],otherinds[i]), length(otherinds))
  inds2 = ntuple(  i->(i==irgbaxis) ? axVal2Index(axlist[i],c2)  : in(i,(ixaxis,iyaxis)) ? (:) : axVal2Index(axlist[i],otherinds[i]), length(otherinds))
  inds3 = ntuple(  i->(i==irgbaxis) ? axVal2Index(axlist[i],c3)  : in(i,(ixaxis,iyaxis)) ? (:) : axVal2Index(axlist[i],otherinds[i]), length(otherinds))

  a1 = d[inds1...]
  a2 = d[inds2...]
  a3 = d[inds3...]

  if p.dmin==p.dmax
    mir,mar,mig,mag,mib,mab=(getMinMax(a1)...,getMinMax(a2)...,getMinMax(a3)...)
  else
    mir,mar = dmin[1],dmax[1]
    mig,mag = dmin[2],dmax[2]
    mib,mab = dmin[3],dmax[3]
  end

  rgbar=getRGBAR(p.cType,a1,a2,a3,(mir,mig,mib),(mar,mag,mab),p.misscol,p.oceancol)
  pngbuf=IOBuffer()
  show(pngbuf,"image/png",transpose(reshape(rgbar,size(rgbar,1),size(rgbar,2))))
  themap=compose(context(0,0,1,1),bitmap("image/png",pngbuf.data,0,0,1,1))
end



abstract type MAPPlotMapped <: MAPPlot end

plotAxVars(p::MAPPlotMapped)=[FixedAx(p.xaxis,"X Axis",true,false,1),FixedAx(p.yaxis,"Y Axis",true,false,2)]


mutable struct MAPPlotCategory <: MAPPlotMapped
  colorm
  colorm2
  oceancol
  misscol
  xaxis
  yaxis
  im_only
end

toMatrix(a::Array)=reshape(a,size(a,1),size(a,2))
function plotCall(p::MAPPlotCategory,d::AbstractCubeData, ixaxis, iyaxis,otherinds...)

  axlist = caxes(d)
  inds = ntuple(i->in(i,(ixaxis,iyaxis)) ? (:) : axVal2Index(axlist[i],otherinds[i]), length(otherinds))

  a = d[inds...]


  if p.im_only
    _makeMaprgb(a,0.0,0.0,(p.colorm,p.colorm2),p.oceancol,p.misscol,:right,true,false,[])[5]
  else
    _makeMap(a,0.0,0.0,(p.colorm,p.colorm2),p.oceancol,p.misscol,:right,true,false,[])
  end
end


mutable struct MAPPlotContin <: MAPPlotMapped
  colorm
  dmin
  dmax
  symmetric
  oceancol
  misscol
  xaxis
  yaxis
  tickspos
  im_only
end

function plotCall(p::MAPPlotContin, d::AbstractCubeData, ixaxis, iyaxis, otherinds...)

  axlist = caxes(d)
  inds = ntuple(i->in(i,(ixaxis,iyaxis)) ? (:) : axVal2Index(axlist[i],otherinds[i]), length(otherinds))

  a = d[inds...]

  if p.dmin==p.dmax
    mi,ma=getMinMax(a)
  else
    mi=p.dmin
    ma=p.dmax
  end

  if p.im_only
    _makeMaprgb(a,mi,ma,p.colorm,p.oceancol,p.misscol,:bottom,false,p.symmetric,p.tickspos)[5]
  else
    _makeMap(a,mi,ma,p.colorm,p.oceancol,p.misscol,:bottom,false,p.symmetric,p.tickspos)
  end
end

"""
    plotMAP(cube::AbstractCubeData; dmin=datamin, dmax=datamax, colorm=colormap("oranges"), oceancol=colorant"darkblue", misscol=colorant"gray", kwargs...)

Map plotting tool for cube objects, can be called on any type of cube data

### Keyword arguments

* `dmin, dmax` Minimum and maximum value to be used for color transformation
* `colorm` colormap to be used. Find a list of colormaps in the [Colors.jl](https://github.com/JuliaGraphics/Colors.jl) package
* `oceancol` color to fill the ocean with, defaults to `colorant"darkblue"`
* `misscol` color to represent missing values, defaults to `colorant"gray"`
* `symmetric` make the color scale symmetric around zero
* `xaxis` which axis should be used for x axis, defaults to `LonAxis`
* `yaxis` which axis should be used for y axis, defaults to `LatAxis`
* `dim=value` can set other dimensions to certain values, for example `var="air_temperature_2m"` will fix the variable for the resulting plot
If a dimension is neither longitude or latitude and is not fixed through an additional keyword, a slider or dropdown menu will appear to select the axis value.

If the properties field of `cube` contains a "labels" field with a dictionary mapping field values to
the name of the class represented.
"""
function plotMAP(cube::CubeAPI.AbstractCubeData{T};xaxis=LonAxis, yaxis=LatAxis, dmin=zero(T),dmax=zero(T),
  colorm=:inferno,oceancol=colorant"darkblue",misscol=colorant"gray",symmetric=false, tickspos=[],im_only=false,kwargs...) where T

  isa(colorm,Symbol) && (colorm=get(namedcolms,colorm,namedcolms[:inferno]))
  dmin,dmax=typed_dminmax(T,dmin,dmax)
  axlist=caxes(cube)

  props=cubeproperties(cube)

  if haskey(props,"labels")
    labels = props["labels"]
    _colorm  = distinguishable_colors(length(labels)+2,[misscol,oceancol])[3:end]
    colorm   = Dict(k=>_colorm[i] for (i,k) in enumerate(keys(labels)))
    colorm2  = Dict(k=>_colorm[i] for (i,k) in enumerate(values(labels)))
    plotGeneric(MAPPlotCategory(colorm,colorm2,oceancol,misscol,xaxis,yaxis,im_only),cube;kwargs...)
  else
    plotGeneric(MAPPlotContin(colorm,dmin,dmax,symmetric,oceancol,misscol,xaxis,yaxis,tickspos,im_only),cube;kwargs...)
  end
end

"""
    plotMAPRGB(cube::AbstractCubeData; dmin=datamin, dmax=datamax, colorm=colormap("oranges"), oceancol=colorant"darkblue", misscol=colorant"gray", kwargs...)

Map plotting tool for colored plots that use up to 3 variables as input into the several color channels.
Several color representations from the `Colortypes.jl` package are supported, so that besides RGB (XYZ)-plots
one can create HSL, HSI, HSV or Lab and Luv plots.

### Keyword arguments

* `dmin, dmax` Minimum and maximum value to be used for color transformation, can be either a single value or a tuple, when min/max values are given for each channel
* `rgbaxis` which axis should be used to select RGB channels from
* `oceancol` color to fill the ocean with, defaults to `colorant"darkblue"`
* `misscol` color to represent missing values, defaults to `colorant"gray"`
* `labels` given a list of labels this will create a plot with a non-continouous color scale where integer cube values [1..N] are mapped to the given labels.
* `cType` ColorType to use for the color representation. Can be one of `RGB`, `XYZ`, `Lab`, `Luv`, `HSV`, `HSI`, `HSL`
* `dim=value` can set other dimensions to certain values, for example `var="air_temperature_2m"` will fix the variable for the resulting plot
* `c1`, `c2`, `c3` values on the first, second, third colour channel


If a dimension is neither longitude or latitude and is not fixed through an additional keyword, a slider or dropdown menu will appear to select the axis value.
"""
function plotMAPRGB(cube::CubeAPI.AbstractCubeData{T};dmin=zero(T),dmax=zero(T),
  rgbaxis=VariableAxis,oceancol=colorant"darkblue",misscol=colorant"gray",symmetric=false,
  c1 = nothing, c2=nothing, c3=nothing, cType=XYZ, xaxis=LonAxis,yaxis=LatAxis,kwargs...) where T

  dmin,dmax = typed_dminmax2(T,dmin,dmax)
  axlist    = caxes(cube)

  irgb = findAxis(rgbaxis,axlist)
  if length(axlist[irgb])==3 && c1==nothing && c2==nothing && c3==nothing
    c1=1
    c2=2
    c3=3
  end

  return plotGeneric(MAPPlotRGB(xaxis,yaxis,rgbaxis,dmin,dmax,c1,c2,c3,misscol,oceancol,cType),cube;kwargs...)
end

@noinline getRGBAR(a,colorm,mi,ma,misscol,oceancol)=RGB{U8}[val2col(a[i,j],colorm,mi,ma,misscol,oceancol) for j=1:size(a,2),i=1:size(a,1)]
@noinline getRGBAR(cType,ar,ag,ab,mi,ma,misscol,oceancol)=map((ar,ag,ab)->RGB(val2col(cType,ar,ag,ab,mi,ma,misscol,oceancol)),ar,ag,ab)
@noinline getRGBAR(a,colorm::Dict,mi,ma,misscol,oceancol)=RGB{U8}[val2col(a[i,j],colorm,misscol,oceancol) for j=1:size(a,2),i=1:size(a,1)]

using ColorTypes
channel_max(d::DataType)="Colortype $d not yet added"
const RGBlike=Union{Type{XYZ},Type{RGB},Type{xyY}}
const HSVlike=Union{Type{HSV},Type{HSI},Type{HSL}}
const Lablike=Union{Type{Lab},Type{Luv}}
channel_min(::RGBlike)=(0.0,0.0,0.0)
channel_max(::RGBlike)=(1.0,1.0,1.0)
channel_min(::Lablike)=(0.0,-170.0,-100.0)
channel_max(::Lablike)=(100.0,100.0,150.0)
channel_min(::HSVlike)=(0.0,0.0,0.0)
channel_max(::HSVlike)=(360.0,1.0,1.0)
channel_names(::Type{RGB})=("R","G","B")
channel_names(::Type{XYZ})=("X","Y","Z")
channel_names(::Type{xyY})=("x","y","Y")
channel_names(::Type{HSV})=("H","S","V")
channel_names(::Type{HSI})=("H","S","I")
channel_names(::Type{HSL})=("H","S","L")
channel_names(::Type{Lab})=("L","a","b")
channel_names(::Type{Luv})=("L","u","v")

import Showoff.showoff
function getlegend(xmin,xmax,colm,legheight,tickspos)
  xoffs=0.05
  xl=1-2xoffs
  if isempty(tickspos)
      tlabs,smin,smax=optimize_ticks(Float64(xmin),Float64(xmax),extend_ticks=false,k_min=4)
  else
      tlabs = tickspos
  end
  tpos=[(tlabs[i]-xmin)/(xmax-xmin) for i=1:length(tlabs)]
  r=rectangle([(i-1)/length(colm) for i in 1:length(colm)],[0],[1/(length(colm)-1)],[1])
  f=fill([colm[div((i-1)*length(colm),length(colm))+1] for i=1:length(colm)])
  bar=compose(context(xoffs,0.35,xl,0.55),r,f,stroke(nothing),svgattribute("shape-rendering","crispEdges"))
  tlabels=compose(context(xoffs,0,xl,0.2),text(tpos,[1],showoff(tlabs),[HCenter()],[VBottom()]))
  dlines=compose(context(xoffs,0.25,xl,0.1),line([[(tpx,0.1),(tpx,0.9)] for tpx in tpos]),stroke(colorant"black"))
  compose(context(0,1Measures.h-legheight,1,legheight),bar,tlabels,dlines)
end

function getlegend(colm,width)
  texth1=Compose.max_text_extents(Compose.default_font_family, Compose.default_font_size, first(keys(colm)))[2]
  texth=texth1*1.05*length(colm)
  yoffs=(Measures.h-texth)/2
  yl=texth
  ncol=length(colm)
  tpos=[(i-0.5)/ncol for i=1:ncol]
  r=Compose.circle([0.5],[(i-0.5)/ncol for i in 1:ncol],[max(1/(ncol-1),0.5)])
  f=fill(collect(values(colm)))
  bar=compose(context(0.9,yoffs,0.1,yl),r,f,stroke(nothing),svgattribute("shape-rendering","crispEdges"))
  tlabels=compose(context(0,yoffs,0.85,yl),Compose.text([1],tpos,collect(keys(colm)),[HRight()],[VCenter()]))
  compose(context(1Measures.w-width,0,width,1),bar,tlabels)
end


import ESDL.Cubes.Mask: isvalid, isocean
function getMinMax(x::AbstractArray{<:Union{T,Missing}};symmetric=false) where T
  mi=typemax(T)
  ma=typemin(T)
  for ix in x
    if !ismissing(ix)
      if ix<mi mi=ix end
      if ix>ma ma=ix end
    end
  end
  if mi==typemax(T) || ma==typemin(T)
    mi,ma=(zero(T),one(T))
  elseif mi==ma
    mi,ma=(mi,mi+1)
  end
  if symmetric
    m=max(abs(mi),abs(ma))
    mi=-m
    ma=m
  end
  mi,ma
end

function val2col(x,colorm,mi,ma,misscol,oceancol)
  N=length(colorm)
  #println(x)
  if !ismissing(x) && x<typemax(x)
    i=ceil(Int,min(N,max(1.0,(x-mi)/(ma-mi)*N)))
    return colorm[i]
  #elseif (m & OCEAN)==OCEAN
  #  return oceancol
  else
    return misscol
  end
end

function val2col(cType,xr,xg,xb,mi,ma,misscol,oceancol)
  mi1,mi2,mi3=channel_min(cType)
  ma1,ma2,ma3=channel_max(cType)
  if !any(ismissing,(xr,xg,xb))
    return cType((xr-mi[1])/(ma[1]-mi[1])*(ma1-mi1)+mi1,(xg-mi[2])/(ma[2]-mi[2])*(ma2-mi2)+mi2,(xb-mi[3])/(ma[3]-mi[3])*(ma3-mi3)+mi3)
  #elseif (mr & OCEAN)==OCEAN
  #  return oceancol
  else
    return misscol
  end
end

function val2col(x,colorm::Dict,misscol,oceancol)
  if !isnan(x)
    return get(colorm,x,misscol)
  #elseif (m & OCEAN)==OCEAN
  #  return oceancol
  else
    return misscol
  end
end

function _makeMaprgb(a::Array{T},mi,ma,colorm,oceancol,misscol,legPos,iscategorical,symmetric,tickspos) where T
  if iscategorical
    @assert isa(colorm, Tuple)
    colorm,colorm2=colorm
  else
    mi==ma && ((mi,ma)=getMinMax(a,symmetric=symmetric))
    colorm2=nothing
  end
  colorm, colorm2, mi,ma,getRGBAR(a,colorm,convert(T,mi),convert(T,ma),misscol,oceancol)
end
function _makeMap(a::Array{T},mi,ma,colorm,oceancol,misscol,legPos,iscategorical,symmetric,tickspos) where T
  if !iscategorical
    mi==ma && ((mi,ma)=getMinMax(a,symmetric=symmetric))
  end
  colorm, colorm2, mi,ma,rgbar = _makeMaprgb(a,mi,ma,colorm,oceancol,misscol,legPos,iscategorical,symmetric,tickspos)
  pngbuf=IOBuffer()
  show(pngbuf,"image/png",rgbar)
  legheight=legPos==:bottom ? max(0.1*Measures.h,1.6Measures.cm) : 0Measures.h
  legwidth =legPos==:right  ? max(0.2*Measures.w,3.2Measures.cm) : 0Measures.w
  themap=compose(context(0,0,1Measures.w-legwidth,1Measures.h-legheight),bitmap("image/png",pngbuf.data,0,0,1,1))
  theleg=iscategorical ? getlegend(colorm2,legwidth) : getlegend(mi,ma,colorm,legheight,tickspos)
  compose(context(),themap,theleg)
end
