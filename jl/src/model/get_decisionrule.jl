include("model_details.jl")

module get_decisionrule

    import Main.polydef: polydetails, linsoldetails, solutiondetails
    import Main.model_details: get_shockdetails, decr_euler, model_details_ss, decrlin, msv2xx, dgemv, exogposition
    import Main.linear_solution: get_aimsolution,lindecrule_markov
    using Random
    using DelimitedFiles
    #using DSGE
    export nonlinearsolver

function dgemm(alpha,A,B)
    alpha :: Float64
    A :: Array{Float64}
    B :: Array{Float64}
    
    C=alpha*A*B
    
    return C
    
end
    

function fixedpoint(params,poly,alphacoeff0,slopeconxx,bbt,bbtinv,xgrid,statezlbinfo)

    #Input
    poly :: polydetails
    bbt :: Array{Float64}
    bbtinv :: Array{Float64}
    xgrid :: Array{Float64}
    params :: Array{Float64}
    alphacoeff0 :: Array{Float64}
    slopeconxx :: Array{Float64}
    statezlbinfo :: Array{Int64}
    
    #Initilize variables
    alphacoeffstar=zeros(poly.nfunc*poly.ngrid,2*poly.ns)

    niter = 150
    tolfun = 1.0e-04 #NORMALLY SET TO 1.0e-4, BUT FOR TESTING SET IT LOWER
    step = 7.0e-01
    alphacur = Array{Float64}(undef,poly.nfunc*poly.ngrid,2*poly.ns)
    alphass = Array{Float64}(undef,2*poly.nfunc,poly.ngrid)
    alphanew = Array{Float64}(undef,poly.nfunc*poly.ngrid,2*poly.ns) 
        #fill!(alphanew,NaN) # Need to fill alphanew with NaN to check later

    alphacur = copy(alphacoeff0)
    convergence = false
    for ii in 1:niter
        avgerror = 0.0
        @time for ss in 1:poly.ns
            polyappnew = zeros(2*poly.nfunc,poly.ngrid)
            errsum_grid = 0.0
            for igrid in 1:poly.ngrid
                polyappnew[:,igrid],errsum,errmax=decr_euler(igrid,ss,params,poly,alphacur,slopeconxx,bbt,xgrid,statezlbinfo[ss]) #NEED TO REWORK THIS FUNCTION SETUP
                errsum_grid = errsum_grid + errsum 
            end

            nrow = 2*poly.nfunc
            alphass=dgemm(1.0,polyappnew,bbtinv) # MAKE SURE THIS WORKS
            for igrid in 1:poly.ngrid
                for ifunc in 1:poly.nfunc
                    alphanew[(ifunc-1)*poly.ngrid+igrid,ss] = alphass[ifunc,igrid] #ALPHASS IS COMING FROM DGEMM ABOVE
                    alphanew[(ifunc-1)*poly.ngrid+igrid,poly.ns+ss] = alphass[poly.nfunc+ifunc,igrid]
                end
            end
            avgerror = avgerror + errsum_grid/poly.ngrid
            
        end
        avgerror = avgerror/(2*poly.ns) 

        if (any([isnan(a) for a in alphanew])==true)
            convergence = false
            alphacoeffstar = alphacur
            return alphacoeffstar,convergence,avgerror
        end

        if (avgerror < tolfun)
            convergence = true
            alphacoeffstar = alphacur
            return alphacoeffstar,convergence,avgerror
        end
        alphacur = (1.0-step)*alphacur + step*alphanew
    end
              
    return alphacoeffstar,convergence,avgerror

end


function simulate_linear(linsol,ns,nmsv,shockbounds,shockdistance,nshockgrid)

    # Input
    linsol :: linsoldetails
    nmsv :: Int64
    ns :: Int64
    shockbounds :: Array{Float64}
    shockdistance :: Array{Float64}
    nshockgrid :: Array{Int64}
        
    # Initilize Variables
    capt = 100000
    statezlbinfo = zeros(Int64,ns)
    endog_emean = Array{Float64}(undef,linsol.nvars)
    msvbounds = Array{Float64}(undef,2*(nmsv+linsol.nexogcont))
    shockindex = Array{Int64}(undef,linsol.nexog-linsol.nexogcont)
    countzlbstates = zeros(Int64,ns)
    msvhigh = Array{Float64}(undef,nmsv,1)
    msvlow = Array{Float64}(undef,nmsv,1)
    innovations = Array{Float64}(undef,linsol.nexog,1)
    xrandn = Array{Float64}(undef,linsol.nexog,capt)
    msv_std = zeros(nmsv+linsol.nexogcont)
    endogvar=zeros(linsol.nvars,capt+1)

    #get random normals
    iseed = MersenneTwister(101294)
    randn!(iseed,xrandn)  

    
    #FOR TESTING
    xrandnFortran=readdlm("xrandn.txt")
    xrandn=reshape(xrandnFortran,linsol.nexog,capt)

    nmsvplus = nmsv + linsol.nexogcont
    convergence = true

    counter = 1
    countzlb = 0
    displacement = 400
    endogvar[1:nmsv,1] = linsol.endogsteady[1:nmsv]
    msvhigh = log.(exp.(linsol.endogsteady[1:nmsv])*2.0)
    msvlow = log.(exp.(linsol.endogsteady[1:nmsv])*0.01)
    count_exploded = 0

    while true
        explosiveerror = false
        llim = counter+1
        ulim = min(capt+1,counter+displacement)
	
        for ttsim in llim:ulim
            innovations[1:linsol.nexogshock] = xrandn[1:linsol.nexogshock,ttsim-1]
            if (linsol.nexogcont > 0) 
                innovations[linsol.nexog-linsol.nexogcont+1:linsol.nexog] = xrandn[linsol.nexog-linsol.nexogcont+1:linsol.nexog,ttsim-1]
            end
            endogvar[:,ttsim] = decrlin(endogvar[:,ttsim-1],innovations,linsol)
            if (endogvar[5,ttsim] < 0.0)
                countzlb = countzlb + 1
                fill!(shockindex,1)
                for i in 1:linsol.nexogshock
                    if (endogvar[linsol.nvars-linsol.nexog+i,ttsim] < shockbounds[i,1]) 
                        shockindex[i] = 1
                    else  #interpolation case
                        shockindex[i]  = min( nshockgrid[i], floor(1.0+(endogvar[linsol.nvars-linsol.nexog+i,ttsim]-shockbounds[i,1])/shockdistance[i]) )#Fortran defaults to round down so I do as well
                    end
                end
                stateindex = exogposition(shockindex,nshockgrid,linsol.nexog-linsol.nexogcont) #MAY HAVE TO CONVERY ARRAY TO INT
                countzlbstates[stateindex] = countzlbstates[stateindex] + 1
                if (countzlbstates[stateindex] > 5)
                    statezlbinfo[stateindex] = 1 
                end
            end
        end

        # Checkloop
        for ttsim in llim:ulim
            non_explosive = ( all(msvlow.<endogvar[1:nmsv,ttsim].<msvhigh) ) 
            explosiveerror = ( (non_explosive == false) | (isnan(endogvar[1,ttsim]) == true) )
            if (explosiveerror == true)
                counter = max(ttsim-200,0)
                #randn!(iseed,xrandn) 
                if (explosiveerror == true) 
                    println("solution exploded at ", ttsim, " vs ulim ", ulim)
                    count_exploded = count_exploded + 1
                end
          
                if (counter == 0)
                    convergence = false
                    println("degenerated back to the beginning")
                end
                break
            end
        end
        
        if (count_exploded == 50)
            println("linear solution exploded for the 50th time")
            convergence = false
        end 

        if (convergence  == false)
	    zlbfrequency = 100.0*countzlb/capt
    	    scalebd = 3.0
    	    endog_emean = sum(endogvar[:,2:(capt+1)], dims=2)/capt
            return endog_emean,zlbfrequency,msvbounds,statezlbinfo,convergence
        end

        if (explosiveerror == false)
            counter = counter + displacement
        end

        if (counter > capt+1)
            break
        end

    end

    #calculate mean of all variables; std. dev of minimum state variables and exogenous variables
    #that we include in polynomial part of approximated decision rule
    zlbfrequency = 100.0*countzlb/capt
    scalebd = 3.0
    endog_emean = sum(endogvar[:,2:capt+1],dims=2)/capt

    for counter in 1:nmsv
        msv_std[counter] = sqrt( sum( (endogvar[counter,2:capt+1].-endog_emean[counter]).^2 )/(capt-1) )
    end
    
    msvbounds[1:nmsv] = endog_emean[1:nmsv]-scalebd*msv_std
    msvbounds[nmsvplus+1:nmsvplus+nmsv] = endog_emean[1:nmsv]+scalebd*msv_std

    #I RE WROTE THIS PART SINCE IT DIDNT MAKE SENSE
    for counter in 1:linsol.nexogcont
        
        msv_std[nmsv+counter] = sqrt( sum( (endogvar[linsol.nvars-counter+1,2:capt+1] -endog_emean[linsol.nvars-counter+1]).^2 )/(capt-1) )
        msvbounds[nmsv+counter] = endog_emean[linsol.nvars-counter+1]-scalebd*msv_std[nmsv+counter]
        msvbounds[nmsvplus+nmsv+counter] = endog_emean[linsol.nvars-counter+1]+scalebd*msv_std[nmsv+counter]
    end
    
    return endog_emean,zlbfrequency,msvbounds,statezlbinfo,convergence
                                                                                
end 

function initialalphas(nfunc,ngrid,ns,nvars,nexog,nexogshock,nexogcont,nmsv,exoggrid,slopeconxx,xgrid,bbtinv,aalin,bblin,endogsteady)

    #Input
    nfunc :: Int64
    ngrid :: Int64
    ns :: Int64
    nvars :: Int64
    nexog :: Int64
    nmsv :: Int64
    nexogshock :: Int64
    nexogcont :: Int64
    exoggrid :: Array{Float64}
    slopeconxx :: Array{Float64}
    xgrid :: Array{Float64}
    bbtinv :: Array{Float64}
    aalin :: Array{Float64}
    bblin :: Array{Float64}
    endogsteady :: Array{Float64}

    #Initilize variables       
    endogvar = Array{Float64}(undef,nvars)
    exogpart = Array{Float64}(undef,nvars)
    slopeconxxmsv = Array{Float64}(undef,2*nmsv)
    slopeconcont = Array{Float64}(undef,2*nexogcont)
    initialalphas = zeros(nfunc*ngrid,2*ns)
    alphass = zeros(nfunc,ngrid)
    endogvarm1 = zeros(nvars,ngrid)
    
    nmsvplus = nmsv + nexogcont
    slopeconxxmsv[1:nmsv] = slopeconxx[1:nmsv]
    slopeconxxmsv[nmsv+1:2*nmsv] = slopeconxx[nmsvplus+1:nmsvplus+nmsv]
    if (nexogcont > 0)
        slopeconcont[1:nexogcont] = slopeconxx[nmsv+1:nmsvplus]
        slopeconcont[nexogcont+1:2*nexogcont] = slopeconxx[nmsvplus+nmsv+1:2*nmsvplus]   
    end

    for i in 1:ngrid
        endogvarm1[1:nmsv,i] = msv2xx(xgrid[1:nmsv,i],nmsv,slopeconxxmsv)-endogsteady[1:nmsv] #CHECK THIS FUNCTION
    end

    for ss in 1:ns
        yy = zeros(nfunc,ngrid)
        exogval = zeros(nexog)
        for i in 1:ngrid
            exogval[1:nexogshock] = exoggrid[1:nexogshock,ss]   #update shocks (in deviation from ss)
            if (nexogcont > 0)
                exogval[nexog-nexogcont+1:nexog] = msv2xx(xgrid[nmsv+1:nmsv+nexogcont,i],nexogcont,slopeconcont)-endogsteady[nvars+nexog-nexogcont+1:nvars+nexog]
            end

            #get linear solution
            endogvar=dgemv(1.0, aalin, endogvarm1[:,i]) #REMAKE THIS FUNCTION
            exogpart=dgemv(1.0, bblin, exogval) # REMAKE THIS FUNCTION 
            endogvar = endogsteady[1:nvars] + endogvar + exogpart
            yy[:,i] = endogvar[[10,11,18,19,21,22,13] ]
        end
  
        alphass=dgemm(1.0,yy,bbtinv) #REMAKE THIS FUNCTION

        for i in 1:ngrid
            for ifunc in 1:nfunc
                #if (alphass(ifunc,i) < 1.0e-8) alphass(ifunc,i) = 0.0d0
                initialalphas[(ifunc-1)*ngrid+i,ss] = alphass[ifunc,i]
                #initial guess for ZLB polynomials
                initialalphas[(ifunc-1)*ngrid+i,ns+ss] = alphass[ifunc,i]
            end
        end
    end

    return initialalphas
    
end 


function nonlinearsolver(params,solution)

    #Input
    solution :: solutiondetails
    params :: Array{Float64}

    #Initilize Values
    statezlbinfo = Array{Int64}(undef,solution.poly.ns,1)
    aalin = Array{Float64}(undef,solution.poly.nvars,solution.poly.nvars)
    bblin = Array{Float64}(undef,solution.poly.nvars,solution.poly.nexog)
    alphacoeff0 = Array{Float64}(undef,solution.poly.nfunc*solution.poly.ngrid,2*solution.poly.ns)
    alphacoeffstar = Array{Float64}(undef,solution.poly.nfunc*solution.poly.ngrid,2*solution.poly.ns)
    msvbounds = Array{Float64}(undef,2*(solution.poly.nmsv+solution.poly.nexogcont),1)
    slopeconxx = Array{Float64}(undef,2*(solution.poly.nmsv+solution.poly.nexogcont),1)
    endog_emean = Array{Float64}(undef,solution.poly.nvars+solution.poly.nexog,1)

    #get shock details
    solution.poly.exoggrid,solution.poly.shockbounds,solution.poly.shockdistance=get_shockdetails(solution.poly.nparams,solution.poly.nexog,solution.poly.nexogshock,solution.poly.nexogcont,solution.poly.ns,solution.number_shock_values,solution.poly.nshockgrid,params,solution.exogvarinfo)

    #get bounds after computing variances from linear solution; 
    #also decide which exogenous grid points need 2 polynomials instead of 1 based on whether ZLB is reached using linear solution
    solution.poly.endogsteady = model_details_ss(params,solution.linsol.nvars,solution.poly.nparams)
    solution.linsol.endogsteady = solution.poly.endogsteady
    params,solution.linsol=get_aimsolution(params,solution.linsol) #NEED TO ADD THIS FUNCTION

   endog_emean,zlbfrequency,msvbounds,statezlbinfo,convergence=simulate_linear(solution.linsol,solution.poly.ns,solution.poly.nmsv,solution.poly.shockbounds,solution.poly.shockdistance,solution.poly.nshockgrid)

    
    #check to see how many times the linear model wants a  "nearly-explosive" path
    if (convergence == false)
       return solution, convergence
    end
    
    nmsvplus = solution.poly.nmsv+solution.poly.nexogcont
    solution.poly.slopeconmsv[1:nmsvplus] = 2.0./(msvbounds[nmsvplus+1:2*nmsvplus]-msvbounds[1:nmsvplus]) #element wise division use "./" 
    solution.poly.slopeconmsv[nmsvplus+1:2*nmsvplus] = -2.0*msvbounds[1:nmsvplus]./(msvbounds[nmsvplus+1:2*nmsvplus].-msvbounds[1:nmsvplus]).-1.0
    slopeconxx[1:nmsvplus] = 0.5*(msvbounds[nmsvplus+1:2*nmsvplus]-msvbounds[1:nmsvplus])
    slopeconxx[nmsvplus+1:2*nmsvplus] = msvbounds[1:nmsvplus] + 0.5*(msvbounds[nmsvplus+1:2*nmsvplus]-msvbounds[1:nmsvplus])

    #if no starting guess, construct one from linear solution
    if (solution.startingguess == false)
        aalin,bblin=lindecrule_markov(solution.linsol) #NEED TO ADD THIS FUNCTION
        
        alphacoeff0 = initialalphas(solution.poly.nfunc,solution.poly.ngrid,
            solution.poly.ns,solution.poly.nvars,solution.poly.nexog,solution.poly.nexogshock,
            solution.poly.nexogcont,solution.poly.nmsv,solution.poly.exoggrid,slopeconxx,solution.xgrid,solution.bbtinv,
            aalin,bblin,solution.poly.endogsteady)
        
    else
        alphacoeff0 = solution.alphacoeff
    end
    

    #find metaparameters that solve model 
    alphacoeffstar,convergence,avgerror=fixedpoint(params,solution.poly,alphacoeff0,slopeconxx,solution.bbt,solution.bbtinv,solution.xgrid,statezlbinfo)
    
    solution.alphacoeff = alphacoeffstar

    return solution, convergence
end

end
