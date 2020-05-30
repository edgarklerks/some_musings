using Random
using Pkg

Pkg.add("StatsPlots")
Pkg.add("KernelDensity")

using StatsPlots
using KernelDensity
#=
Small model of a taxi cab getting directions of a random generator

It has a positon and a set of directions. The degree of freedoms it has are
4. It can go:

{Left,Right,Up,Down}

These we can translate to vectors:

(-1 0) (1 0) (0 -1) (0 1)

Which are generators of the group of our taxi cab together with vector addition.



=#
@enum Direction L R U D
@enum Reset Rst
const DirectionVector = Vector{Int64}
const channelBufferSize = 100
const startCompressionRatio = 100

function defaultCabDirection(setSeedChannel :: Channel{Integer}, channel::Channel{Direction}, seed :: Integer)
    generator = MersenneTwister(seed)
    while true
        if isready(setSeedChannel)
            generator = MersenneTwister(take!(setSeedChannel))
        end
        put!(channel,rand(generator,(L,R,U,D)))
    end
end

function dirToVec(dir::Direction) :: DirectionVector
    if dir == L # Left
        return [-1;0]
    elseif dir == R # Right
        return [1;0]
    elseif dir == U # Up
        return [0;1]
    elseif dir == D # Down
        return [0;-1]
    end
end

function directionsMapper(input :: Channel{Direction}, output :: Channel{DirectionVector})
    while true
        dir = take!(input)
        put!(output, dirToVec(dir))
    end
end

#=
We are abusing the group structure of the direction vectors aand the
fact that we are only interested in the position to compress
them very effeciently.
=#
function compressor(compressionRatio :: Int64, setCompressionRatio :: Channel{Int64}, input :: Channel{DirectionVector}, output :: Channel{DirectionVector})
    p = Array{DirectionVector,1}(undef,compressionRatio)
    while true

        if isready(setCompressionRatio)
            compressionRatio = take!(setCompressionRatio)
        end

        for i in 1:compressionRatio
            element = take!(input)
            p[i] = element
        end
        res = sum(p)
        put!(output,res)
    end
end

function observe!(n :: Integer, channel :: Channel{T}) :: Array{T} where T <: Any
    p = Array{T,1}(undef,n)
    for i in 1:n
        e = take!(channel)
        p[i] = e
    end
    return p
end

function observeUnzip!(n :: Integer, channel :: Channel{Vector{T}}) :: Tuple{Array{T},Array{T}} where T <: Any
    x = Array{T}(undef,n)
    y = Array{T}(undef,n)
    for i in 1:n
        e = take!(channel)
        x[i] = e[1]
        y[i] = e[2]
    end
    return (x,y)
end

function destroy!(n :: Integer, channel :: Channel)
    for i in 1:n
        take!(channel)
    end
end

function taxiCab(startPostion :: DirectionVector, reset :: Channel{Reset},  input :: Channel{DirectionVector}, output :: Channel{DirectionVector})
        currentPosition = startPostion
        while true

            if isready(reset)
                rst = take!(reset)
                currentPosition = startPostion
            end

            put!(output,currentPosition)
            dir = take!(input)
            currentPosition = currentPosition + dir
        end
end

directionsChannel = Channel{Direction}(channelBufferSize)
vectorsChannel = Channel{DirectionVector}(channelBufferSize)
compressedChannel = Channel{DirectionVector}(channelBufferSize)
taxiCabPositionChannel = Channel{DirectionVector}(channelBufferSize)
resetTaxiChannel = Channel{Reset}(1)
setCompressionRatioChannel = Channel{Int64}(1)
setSeedChannel = Channel{Integer}(1)
@async defaultCabDirection(setSeedChannel, directionsChannel,1234)
@async directionsMapper(directionsChannel,vectorsChannel)
@async compressor(startCompresssionRatio,setCompressionRatioChannel, vectorsChannel, compressedChannel)
@async taxiCab([0;0],resetTaxiChannel, compressedChannel,taxiCabPositionChannel)


x,y = observeUnzip!(1000, taxiCabPositionChannel)

function resetChannel(channel :: Channel)
    for i in 1:(channelBufferSize)
        take!(channel)
    end
end

# Simple interface to the taxi
function resetWalk(compressionRatio :: Int64, seed :: Integer)
    resetChannel(taxiCabPositionChannel)
    put!(resetTaxiChannel,Rst)
    put!(setCompressionRatioChannel,compressionRatio)
    put!(setSeedChannel, seed)
end

resetWalk(compressionRatio = 100, seed = 1)


density = kde((x,y))
histogram2d(x,y)
heatmap(density)
plot(density)
plot(x,y)
scatter(x,y)
