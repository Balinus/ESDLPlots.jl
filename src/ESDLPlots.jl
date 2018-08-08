module ESDLPlots
export plotTS, plotMAP, plotXY, plotScatter, plotMAPRGB
export plotlyjs, gadfly, gr, pyplot
importall ESDL.Cubes
importall ESDL.CubeAPI
importall ESDL.CubeAPI.Mask
import ESDL.DAT
import ESDL.DAT: findAxis,getFrontPerm
import ESDL.Cubes.Axes.axname
import Reactive: Signal
import Interact: slider, dropdown, signal, togglebutton, togglebuttons, selection_slider
import Colors: RGB, @colorant_str, colormap,  distinguishable_colors
import FixedPointNumbers: Normed
import Base.Cartesian: @ntuple,@nexprs
import Measures
import Compose
import Images
import DataStructures: OrderedDict
import Plots
import Plots: plotlyjs, gr, pyplot
import StatPlots
import PlotUtils: optimize_ticks, cgrad
import Compose: rectangle, text, line, compose, context, stroke, svgattribute, bitmap, HCenter, VBottom, HRight, VCenter


const U8=Normed{UInt8,8}


abstract type ESDLPlot end
"Expression to evaluate after the data is loaded"
getafterEx(::ESDLPlot)=Expr(:block)

"Setting fixed variables"
getFixedVars(::ESDLPlot,cube)=Expr(:block)

mutable struct FixedAx
  axis
  axsym::Symbol
  widgetlabel::String
  musthave::Bool
  isimmu::Bool
  position::Int
end

mutable struct FixedVar
  depAxis
  varVal
  varsym::Symbol
  widgetlabel::String
  musthave::Bool
end

include("maps.jl")
include("other.jl")


toYr(tx::TimeAxis)=((tx.values.startyear+(tx.values.startst-1)/tx.values.NPY):(1.0/tx.values.NPY):(tx.values.stopyear+(tx.values.stopst-1)/tx.values.NPY))-(tx.values.startyear+(tx.values.startst-1)/tx.values.NPY)

r1(x)=reshape(x,length(x))
prepAx(x)=x.values
prepAx(x::TimeAxis)=toYr(x)
function repAx(x,idim,ax)
  l=length(x)
  inrep=prod(size(x)[1:idim-1])
  outrep=div(l,(inrep*size(x,idim)))
  repeat(collect(ax),inner=[inrep],outer=[outrep])
end
function count_to(f,c,i)
  ni=0
  for ind=1:i
    f(c[ind]) && (ni+=1)
  end
  return ni
end

getWidget(x::CategoricalAxis;label=axname(x))       = dropdown(Dict(zip(x.values,1:length(x.values))),label=label)
getWidget(x::RangeAxis{T};label=axname(x)) where {T<:Real} = step(x.values) > 0 ? slider(x.values,label=label) : slider(reverse(x.values),label=label)
getWidget(x::RangeAxis;label=axname(x))             = selection_slider(x.values,label=label)
getWidget(x::SpatialPointAxis;label="Spatial Point")= slider(1:length(x),label=label)

plotTS(x;kwargs...)=plotXY(x;xaxis=TimeAxis,kwargs...)

function setPlotAxis(a::FixedAx,axlist,fixedvarsEx,fixedAxes)
  ix=a.axis==nothing ? 0 : findAxis(a.axis,axlist)
  if ix>0
    push!(fixedvarsEx.args,:($(a.axsym)=$ix))
    push!(fixedAxes,axlist[ix])
    a.axis=ix
  else
    return a.axis = a.isimmu ? error("Axis $(a.axsym) must be selected.") : 0
  end
end
function setPlotAxis(a::FixedVar,axlist,fixedvarsEx,fixedAxes)
  a.depAxis=findAxis(a.depAxis,axlist)
  if a.varVal!=nothing
    push!(fixedvarsEx.args,:($(a.varsym)=$(axVal2Index(axlist[a.depAxis],a.varVal))))
  end
end

function createWidgets(axlist,availableAxis,availableIndices,fixedvarsEx,axlabels,widgets,signals,argvars,axtuples)

  if !isempty(availableAxis)
    for at in axtuples
      if isa(at,FixedAx)
        if at.axis == 0
          options = collect(at.musthave ? zip(axlabels[availableIndices],availableIndices) : zip(["None";axlabels[availableIndices]],[0;availableIndices]))
          axmenu  = dropdown(OrderedDict(options),label=at.widgetlabel,value=options[1][2],value_label=options[1][1])
          sax=signal(axmenu)
          push!(widgets,axmenu)
          push!(argvars,at.axsym)
          push!(signals,sax)
        end
      elseif isa(at,FixedVar)
        if at.varVal==nothing
          w=getWidget(axlist[at.depAxis],label=at.widgetlabel)
          push!(widgets,w)
          push!(signals,signal(w))
          push!(argvars,at.varsym)
        end
      else
        error("")
      end
    end
    for i in availableIndices
      w=getWidget(axlist[i])
      push!(widgets,w)
      push!(signals,signal(w))
      push!(argvars,Symbol(string("v_",i)))
    end
  else
    for at in axtuples
      if (isa(at,FixedAx) && at.axis==0)
        at.musthave && error("No axis left to put on $label")
        push!(fixedvarsEx.args,:($(at.axsym)=0))
      end
    end
  end
end

const namedcolms=Dict(
:viridis=>[cgrad(:viridis)[ix] for ix in linspace(0,1,100)],
:magma=>[cgrad(:magma)[ix] for ix in linspace(0,1,100)],
:inferno=>[cgrad(:inferno)[ix] for ix in linspace(0,1,100)],
:plasma=>[cgrad(:plasma)[ix] for ix in linspace(0,1,100)])
typed_dminmax(::Type{T},dmin,dmax) where {T<:Integer}=(Int(dmin),Int(dmax))
typed_dminmax(::Type{T},dmin,dmax) where {T<:AbstractFloat}=(Float64(dmin),Float64(dmax))
typed_dminmax2(::Type{T},dmin,dmax) where {T<:Integer}=(isa(dmin,Tuple) ? (Int(dmin[1]),Int(dmin[2]),Int(dmin[3])) : (Int(dmin),Int(dmin),Int(dmin)), isa(dmax,Tuple) ? (Int(dmax[1]),Int(dmax[2]),Int(dmax[3])) : (Int(dmax),Int(dmax),Int(dmax)))
typed_dminmax2(::Type{T},dmin,dmax) where {T<:AbstractFloat}=(isa(dmin,Tuple) ? (Float64(dmin[1]),Float64(dmin[2]),Float64(dmin[3])) : (Float64(dmin),Float64(dmin),Float64(dmin)), isa(dmax,Tuple) ? (Float64(dmax[1]),Float64(dmax[2]),Float64(dmax[3])) : (Float64(dmax),Float64(dmax),Float64(dmax)))




function plotGeneric(plotObj::ESDLPlot, cube::CubeAPI.AbstractCubeData{T};kwargs...) where T


  axlist=axes(cube)

  fixedvarsEx=getFixedVars(plotObj,cube)

  axlist=axes(cube)
  axlabels=map(axname,axlist)
  widgets=Any[]
  argvars=Symbol[]
  fixedAxes=CubeAxis[]
  signals=Signal[]

  pAxVars=plotAxVars(plotObj)

  foreach(t->setPlotAxis(t,axlist,fixedvarsEx,fixedAxes),pAxVars)

  positionalFixed = filter(i->isa(i,FixedAx) && i.position>0 && i.axis>0,pAxVars)
  positions = map(i->i.axis,positionalFixed)
  if !issorted(positions)
       transposeEx=:((a_f,m_f) = (transpose(a_f),transpose(m_f)))
  else
    transposeEx=:()
  end

  for (sy,val) in kwargs
    ix = findAxis(string(sy),axlist)
    if ix > 0
      s=Symbol("v_$ix")
      push!(fixedvarsEx.args,:($s=$val))
      push!(fixedAxes,axlist[ix])
    end
  end

  availableIndices=find(ax->!in(ax,fixedAxes),axlist)
  availableAxis=axlist[availableIndices]

  createWidgets(axlist,availableAxis,availableIndices,fixedvarsEx,axlabels,widgets,signals,argvars,pAxVars)

  nax        = length(axlist)
  nCubes     = nplotCubes(plotObj)

  plotfun=quote
    axlist=axes(cube)
    $fixedvarsEx
    ndim=$nax

    subcubedims = Base.Cartesian.@ntuple $nax d->$(makeifs(match_subCubeDims(plotObj).args))
    sd2 = Iterators.filter(i->i>1,subcubedims)

    Base.Cartesian.@nexprs $nCubes f->begin
      a_f        = zeros(eltype(cube), subcubedims)
      m_f        = zeros(UInt8,        subcubedims)
      indstart_f = Base.Cartesian.@ntuple $nax d->$(makeifs(match_indstart(plotObj).args))
      indend_f   = Base.Cartesian.@ntuple $nax d->$(makeifs(match_indend(plotObj).args))
      _read(cube,(a_f,m_f),CartesianRange(CartesianIndex(indstart_f),CartesianIndex(indend_f)))
      a_f,m_f = reshape(a_f,sd2...),reshape(m_f,sd2...)
      $transposeEx
    end

    $(getafterEx(plotObj))
    $(plotCall(plotObj))
  end
  if length(argvars)==0
    x=eval(:(cube->$plotfun))
    return eval(:($x($cube)))
  end
  lambda = Expr(:(->), Expr(:tuple, argvars...),plotfun)
  liftex = Expr(:call,:map,lambda,signals...)
  #return(liftex)
  myfun=eval(quote
    local li
    li(cube)=$liftex
  end)
  #println(macroexpand(liftex))
  foreach(display,widgets)
  r = eval(:($myfun($cube)))
  display(r)
end

end # module
