include("linear_solution.jl")

module model_details

    import Main.polydef: linsoldetails, polydetails, solutiondetails, initializesolution!, setgridsize, exoggridindex, ghquadrature,sparsegrid, smolyakpoly, initializelinearsolution!, initializetestsolution!, gensys
    using LinearAlgebra

    export decr, dgemv, decrlin, model_details_ss, decr_euler, get_shockdetails, calc_premium, msv2xx, exogposition

function float_dot(x,y)
    
    x :: SubArray{Float64,1,Array{Float64,2},Tuple{UnitRange{Int64},Int64},true}
    y :: Array{Float64}
    
    dot=0.0
    @simd for i in 1:length(y)
        dot = dot+x[i]*y[i]
    end
    return dot
    
end

@views view(x,l,u,i) = x[l:u,i]  #More quickly takes slice of an array    

function dgemv(alpha,A,x)
    
    #Input
    alpha :: Real
    A :: Array
    x :: Array
    
    z = alpha*A*x
    
    return z
    
end

function msv2xx(msv,nmsv,slopeconmsv)

    #Input
    nmsv :: Int
    msv :: Array{Float64}
    slopeconmsv :: Array{Float64}
  
    msv2xx = slopeconmsv[1:nmsv].*msv + slopeconmsv[nmsv+1:2*nmsv] 
    
    return msv2xx 
    
end 

function exogposition(exogvec,nrvec,nlength) #FIX THIS FUNCTION ON MONDAY

    # Input
    nlength :: Int64
    nrvec :: Array{Int64}
    exogvec :: Array{Int64}
    
    #Initilize variables
    exogposition =0

    for i=1:1
        if (nlength == 6)
            exogposition = nrvec[6]*nrvec[5]*nrvec[4]*nrvec[3]*nrvec[2]*(exogvec[1]-1) + nrvec[6]*nrvec[5]*nrvec[4]*nrvec[3]*(exogvec[2]-1) + 
            nrvec[6]*nrvec[5]*nrvec[4]*(exogvec[3]-1) + nrvec[6]*nrvec[5]*(exogvec[4]-1) + nrvec[6]*(exogvec[5]-1) + exogvec[6]
        elseif (nlength == 5)
            exogposition = nrvec[5]*nrvec[4]*nrvec[3]*nrvec[2]*(exogvec[1]-1) + nrvec[5]*nrvec[4]*nrvec[3]*(exogvec[2]-1) + 
            nrvec[5]*nrvec[4]*(exogvec[3]-1) + nrvec[5]*(exogvec[4]-1) + exogvec[5]
        elseif (nlength == 4)
            exogposition = nrvec[4]*nrvec[3]*nrvec[2]*(exogvec[1]-1) + nrvec[4]*nrvec[3]*(exogvec[2]-1) + 
            nrvec[4]*(exogvec[3]-1) + exogvec[4]
        elseif (nlength == 3)
            exogposition = nrvec[3]*nrvec[2]*(exogvec[1]-1) + nrvec[3]*(exogvec[2]-1) + exogvec[3]
        elseif (nlength == 2)
            exogposition = nrvec[2]*(exogvec[1]-1) + exogvec[2]
        elseif (nlength == 1)
            exogposition = exogvec[1]
        else
            println("There can only be six shocks. You need to modify exogposition. (exogposition - module polydef).")
            break
        end
    end
        
    return exogposition

end

function intermediatedec(nparams,nvars,nexog,nfunc,endogvarm1,currentshockvalues,params,polyvar,llabss,omegapoly,polyvarplus,zlbintermediate)

    #Input
    nparams :: Int64
    nvars :: Int64
    nexog :: Int64
    nfunc :: Int64
    params :: Array{Float64}
    endogvarm1 :: Array{Float64}
    currentshockvalues :: Array{Float64}
    polyvar :: Array{Float64}
    llabss :: Float64
    omegapoly :: Float64
    polyvarplus :: Array{Float64}
    zlbintermediate :: Bool
    
    #Initilize Variables
    endogvar=Array{Float64}(undef,nvars+nexog,1)  

    #parameters
    beta = params[1] 
    pibar = params[2] 
    gz = params[3] 
    psil = params[4] 
    gamma = params[5] 
    sigmal = params[6]  
    phi = params[7] 
    phiw = params[8] 
    ep = params[9] 
    epw = params[10]  
    ap = params[11] 
    aw = params[12] 
    bw = params[13]  
    lamhp = params[14] 
    alpha = params[15] 
    delta = params[16] 
    phii = params[17]  
    sigmaa = params[18]  
    gam_rs = params[19] 
    gam_dp = params[20] 
    gam_xhp = params[21]  
    gam_dy = params[22]  
    shrgy = params[23] 

    #fix bw = aw
    bw = copy(aw) #I may have to copy so it doesn't become a pointer

    invshk = exp( currentshockvalues[2] )
    techshk = exp( currentshockvalues[3] ) 
    rrshk = currentshockvalues[4]
    gss = 1.0/(1.0-shrgy)
    gshk = exp( log(gss) + currentshockvalues[5] )
    ashk = exp( currentshockvalues[6] )

    capm1 = endogvarm1[1]
    ccm1 = endogvarm1[2]
    invm1 = endogvarm1[3]
    rwm1 = endogvarm1[4]
    notrm1 = endogvarm1[5]
    dpm1 = endogvarm1[6]
    gdpm1 = endogvarm1[7]

    if (zlbintermediate == true) 
        lam = omegapoly*exp(polyvar[1]) + (1.0-omegapoly)*exp(polyvarplus[1])
        qq = omegapoly*exp(polyvar[2]) + (1.0-omegapoly)*exp(polyvarplus[2])
        bp = omegapoly*polyvar[3] + (1.0-omegapoly)*polyvarplus[3]
        bww = omegapoly*polyvar[4] + (1.0-omegapoly)*polyvarplus[4]
        bc = omegapoly*exp(polyvar[5]) + (1.0-omegapoly)*exp(polyvarplus[5])
        bi = omegapoly*polyvar[6] + (1.0-omegapoly)*polyvarplus[6]
        util = omegapoly*exp(polyvar[7]) + (1.0-omegapoly)*exp(polyvarplus[7])
    else
        lam = exp(polyvar[1]) 
        qq = exp(polyvar[2]) 
        bp = polyvar[3]
        bww = polyvar[4]
        bc = exp(polyvar[5]) 
        bi = polyvar[6]
        util = exp(polyvar[7])
    end
   
    vp = (sqrt(1.0+4.0*bp)+1.0)/2.0
    vw = (sqrt(1.0+4.0*bww)+1.0)/2.0
    dptildem1 = (pibar^ap)*(dpm1^(1.0-ap))
    dwtildem1 = (pibar^aw)*(dpm1^(1.0-aw))
    gzwage = gz*techshk^(1.0-bw)
    dp = vp*dptildem1
    dw = vw*dwtildem1*gzwage
    muc = lam + (gamma/gz)*beta*bc
    cc = gamma*ccm1/(gz*techshk)+1.0/muc
    cquad_vi = bi/(qq*invshk)-(1.0-qq*invshk)/(phii*qq*invshk)

    vi = 0.5*(1.0+sqrt(1.0+4.0*cquad_vi))
 
    inv = vi*invm1/techshk
    aayy = 1.0/gshk-(phi/2.0)*(vp-1.0)*(vp-1.0)
    rkss = gz/beta-1.0+delta
    utilcost = (rkss/sigmaa)*(exp(sigmaa*(util-1.0))-1.0)
    gdp = (1.0/aayy)*( cc+inv + utilcost*(capm1/(gz*techshk)) )
    rw = rwm1*dw/(gz*techshk*dp)
    lab = gdp^(1.0/(1.0-alpha))*(util*capm1/(gz*techshk))^(alpha/(alpha-1.0))/ashk
    xhp = alpha*log(util) + (1-alpha)*(log(lab)-llabss)

    lrss = log(gz*pibar/beta)
    notr = exp( lrss+gam_rs*(log(notrm1)-lrss) + (1.0-gam_rs)*( gam_dp*log(dp/pibar) + gam_dy*log(gdp*techshk/gdpm1) + gam_xhp*xhp ) + rrshk )

    mc = rw*lab/((1.0-alpha)*gdp)
    rentalk = (alpha/(1.0-alpha))*(rw*lab*gz*techshk/(util*capm1))
    cap = (1.0-delta)*(capm1/(gz*techshk)) + invshk*inv*(1.0- (phii/2.0)*(vi-1.0)*(vi-1.0) )
    nomr = copy(notr) # copy as to no make it a pointer

    #all variables are in levels except for shocks
    #shocks are in log-level deviations from SS
    #(1) cap, (2) cc, (3) inv, (4) rw, (5) notr, (6) dp, (7) gdp, (8) xhp, (9) nomr, (10) lam, (11) qq, 
    #(12) lab, (13) util, (14) mc, (15) rentalk, (16) muc, (17) vi, (18) vp, (19) vw, (20) dw, (21) bc, (22) bi,
    #(23) liqshk, (24) invshk, (25) techshk, (26) rrshk, (27) gshk, (28) ashk
    
    endogvar = vcat([cap, cc, inv, rw, notr, dp, gdp, xhp, nomr, lam, qq, lab, util, mc, rentalk, muc, vi, vp, vw, dw, bc, bi], currentshockvalues) #Concatenate two arrays
    
    return endogvar
end

function decr(endogvarm1,innovations,params,poly,alphacoeff)   

    #Input
    endogvarm1 :: Array{Float64}
    innovations :: Array{Float64}
    params :: Array{Float64}
    poly :: polydetails
    alphacoeff :: Array{Float64}
    
    #Initilize Variables
    endogvar=Array{Float64}(undef,poly.nvars+poly.nexog,1)  
    shockindexall=ones(Int64,poly.nexog-poly.nexogcont)
    shockindex=Array{Int64}(undef,poly.nexogshock)
    shockindex_inter=Array{Int64}(undef,poly.nexogshock)
    lmsv=Array{Float64}(undef,poly.nmsv+poly.nexogcont)
    currentshockvalues=Array{Float64}(undef,poly.nexog)
    funcmatplus=Array{Float64}(undef,poly.nfunc,poly.ninter)
    weighttemp=Array{Float64}(undef,poly.nexogshock)
    funcapp=Array{Float64}(undef,poly.nfunc)
    funcapp_plus=Array{Float64}(undef,poly.nfunc)
    xx=Array{Float64}(undef,poly.nmsv)
    polyvec=Array{Float64}(undef,poly.ngrid)
    
    omegaweight = 100000.0

    nmsvplus = poly.nmsv+poly.nexogcont

    #shock parameters
    sdevtech = params[24]
    rhog = params[25] 
    sdevg = params[26]
    rhoinv = params[27]
    sdevinv = params[28]
    rholiq = params[29] 
    sdevliq = params[30] 
    rhoint = params[31]
    sdevint = params[32]
    rhoa = params[33]
    sdeva = params[34]

    #update shocks (all shocks in deviation from SS)
    currentshockvalues[1] = rholiq*endogvarm1[23] + sdevliq*innovations[1]
    currentshockvalues[2] = rhoinv*endogvarm1[24] + sdevinv*innovations[2]
    currentshockvalues[3] = sdevtech*innovations[3]
    currentshockvalues[4] = rhoint*endogvarm1[26] + sdevint*innovations[4]
    currentshockvalues[5] =  rhog*endogvarm1[27] + sdevg*innovations[5]
    currentshockvalues[6] = rhoa*endogvarm1[28] + sdeva*innovations[6]

    #find position of shocks for interpolation
    @simd for i in 1:poly.nexogshock
        if (currentshockvalues[i] < poly.shockbounds[i,1])   #extrapolation below
            shockindex[i] = 1
        elseif (currentshockvalues[i] > poly.shockbounds[i,2])  #extrapolation above
            shockindex[i] = floor(Int64,(poly.shockbounds[i,2]-poly.shockbounds[i,1])/poly.shockdistance[i] ) 
        else  
            shockindex[i] = floor(Int64,1.0+(currentshockvalues[i]-poly.shockbounds[i,1])/poly.shockdistance[i])  #interpolation case
        end
    end

    #loop for interpolating between shocks
    shockindexall[1:poly.nexogshock] = shockindex
    stateindex0 = exogposition(shockindexall,poly.nshockgrid,poly.nexog-poly.nexogcont)
    shockindexall[1:poly.nexogshock] = shockindex + poly.interpolatemat[:,poly.ninter]
    stateindex1 = exogposition(shockindexall,poly.nshockgrid,poly.nexog-poly.nexogcont)
    funcmat = zeros(poly.nfunc,poly.ninter)
    weightvec = zeros(poly.ninter,1)
    lmsv[1:poly.nmsv] = log.(endogvarm1[1:poly.nmsv])
    if (poly.nexogcont > 0) 
        lmsv[poly.nmsv+1:poly.nmsv+poly.nexogcont] = currentshockvalues[poly.nexog-poly.nexogcont+1:poly.nexog]
    end
    xx = msv2xx(lmsv,nmsvplus,poly.slopeconmsv)
    
    polyvec = smolyakpoly(nmsvplus,poly.ngrid,poly.nindplus,poly.indplus,xx)
    prod_sd = prod(poly.shockdistance)
    for i in 1:poly.ninter # @inbounds, stops the bounds check
        @fastmath @inbounds @simd for j in 1:poly.nexogshock
            shockindexall[j] = shockindex[j] + poly.interpolatemat[j,i]
            weighttemp[j]=(1-poly.interpolatemat[j,i])*(currentshockvalues[j]-poly.exoggrid[j,stateindex0]) + (poly.interpolatemat[j,i])*(poly.exoggrid[j,stateindex1]-currentshockvalues[j])
        end
        stateindex = exogposition(shockindexall,poly.nshockgrid,poly.nexog-poly.nexogcont) 
        stateindexplus = stateindex+poly.ns  
        @fastmath @inbounds @simd for ifunc in 1:poly.nfunc
            funcmat[ifunc,i] = float_dot(view(alphacoeff,(ifunc-1)*poly.ngrid+1,ifunc*poly.ngrid,stateindex),polyvec)
            funcmatplus[ifunc,i] = float_dot(view(alphacoeff,(ifunc-1)*poly.ngrid+1,ifunc*poly.ngrid,stateindexplus),polyvec)
        end 
        weightvec[poly.ninter-i+1] = prod(weighttemp)/prod_sd
    end
   
    funcapp=dgemv(1.0, funcmat, weightvec) 

    llabss = poly.endogsteady[12]
            
    zlbintermediate = false  #start with evaluation of 1 poly case (omegapoly and 2nd funcapp irrelevant)
    omegapoly = 1.0 #SINCE ZLBINTERMEDIATE IS FALSE
    endogvar=intermediatedec(poly.nparams,poly.nvars,poly.nexog,poly.nfunc,endogvarm1,currentshockvalues,params,funcapp,llabss,omegapoly,funcapp,zlbintermediate) # I NEED TO ADD THIS FUNCTION

    if ( (endogvar[5] < 1.0) & (poly.zlbswitch == true) ) #zlb case
        zlbintermediate = true
        omegapoly = exp(omegaweight*log(endogvar[5])) #now omegapoly and funcapp_plus relevant
        funcapp_plus=dgemv(1.0, funcmatplus, weightvec)
        endogvar=intermediatedec(poly.nparams,poly.nvars,poly.nexog,poly.nfunc,endogvarm1,currentshockvalues,params,funcapp,llabss,omegapoly,funcapp_plus,zlbintermediate) # I NEED TO ADD THIS FUNCTION
        endogvar[9] = 1.0
    end
    
    return endogvar

end


function decrlin(endogvarm1,innovations,linsol)

    # Input
    linsol :: linsoldetails
    innovations :: Array{Float64}
    endogvarm1 :: Array{Float64}
    
    # Initilize variables
    endogvar = Array{Float64}(undef,linsol.nvars)  
    xxm1 = zeros(linsol.nvars) 
    xx = zeros(linsol.nvars)
    exogpart = Array{Float64}(undef,linsol.nvars)

    xxm1[1:linsol.nvars-linsol.nexog] = endogvarm1[1:linsol.nvars-linsol.nexog]-linsol.endogsteady[1:linsol.nvars-linsol.nexog]
    xxm1[linsol.nvars-linsol.nexog+1:linsol.nvars] = endogvarm1[linsol.nvars-linsol.nexog+1:linsol.nvars]

    xx = dgemv(1.0, linsol.pp, xxm1)
    exogpart = dgemv(1.0, linsol.sigma, innovations)
    xx = xx + exogpart

    endogvar[1:linsol.nvars-linsol.nexog] = xx[1:linsol.nvars-linsol.nexog]+linsol.endogsteady[1:linsol.nvars-linsol.nexog]
    endogvar[linsol.nvars-linsol.nexog+1:linsol.nvars] = xx[linsol.nvars-linsol.nexog+1:linsol.nvars]

    return endogvar
end

            
function model_details_ss(params,nvars,nparams)  #originally named steadystate

    #Input
    nvars :: Int64
    nparams :: Int64
    params :: Array{Float64}
    
    #Initilize Variables
    steadystate = Array{Float64}(undef,nvars,1)

    beta = params[1] 
    pibar = params[2] 
    gz = params[3] 
    psil = params[4] 
    gamma = params[5] 
    sigmal = params[6]  
    phi = params[7] 
    phiw = params[8] 
    ep = params[9] 
    epw = params[10] 
    ap = params[11] 
    aw = params[12] 
    bw = params[13]  
    lamhp = params[14] 
    alpha = params[15] 
    delta = params[16] 
    phii = params[17]  
    sigmaa = params[18] 
    gam_rs = params[19] 
    gam_dp = params[20] 
    gamxhp = params[21] 
    gamdy = params[22] 
    shrgy = params[23] 

    #fix bw = aw (doesn't matter for SS but done anyway for consistency)
    bw = copy(aw)

    #composite parameters and steady state calculations
    gg = 1.0/(1.0-shrgy)
    gamtil = gamma/gz
    mc = (ep-1.0)/ep
    k2yrat = ((mc*alpha)/(gz/beta-(1.0-delta)))*gz
    shriy = (1.0-(1.0-delta)/gz)*k2yrat
    shrcy = 1.0-shrgy-shriy
    labss = ( ((epw-1.0)/epw)*(1.0-alpha)*(1.0-beta*gamtil)*((ep-1.0)/ep)*(1.0/(psil*(1.0-gamtil)))*(1.0/shrcy) )^(1.0/(sigmal+1.0))
    kappaw = ((1.0-gamtil)/(1.0-beta*gamtil))*epw*psil*labss^(1.0+sigmal)/phiw
    kappap = (ep-1.0)/(phi*(1.0+beta*(1.0-ap)))
    #print*,'kappap',kappap, kappap/(ep-1.0d0)
    kss = labss*(gz^(alpha/(alpha-1.0)))*k2yrat^(1.0/(1.0-alpha))
    gdpss = (kss/gz)^alpha*labss^(1.0-alpha)
    invss = shriy*gdpss
    phii_jpt = phii/invss
    css = shrcy*gdpss
    rwss = (1.0-alpha)*mc*gdpss/labss
    mucss = (1.0/css)*(1.0/(1.0-gamtil))
    lamss = mucss*(1.0-beta*gamtil)
    rss = gz*pibar/beta
    rkss = gz/beta-1.0+delta

    #(1) cap, (2) cc, (3) inv, (4) rw, (5) notr, (6) dp, (7) gdp, (8) xhp, (9) nomr, (10) lam, (11) qq, (12) lab, (13) util, (14) mc, (15) rentalk, (16) muc
    #(17) vi, (18) vp, (19) vw, (20) dw, (21) bc, (22) bi, (23) liqshk, (24) invshk, (25) techshk, (26) intshk, (27) gshk, (28) ashk
    steadystate = [log(kss),log(css),log(invss),log(rwss),log(rss),log(pibar),log(gdpss),0.0,log(rss),log(lamss),
                0.0,log(labss),0.0,log(mc),log(rkss),log(mucss),0.0,0.0,0.0,log(pibar*gz),log(mucss),0.0,0.0,0.0,0.0,log(gg),0.0]
                
    return steadystate
                
end 

        
function decr_euler(gridindex,shockpos,params,poly,alphacoeff,slopeconxx,bbt,xgrid,zlbinfo)   
    
    #Input
    poly :: polydetails
    shockpos :: Int64
    gridindex :: Int64
    params :: Array{Float64}
    bbt :: Array{Float64}
    xgrid :: Array{Float64}
    alphacoeff :: Array{Float64}
    slopeconxx :: Array{Float64}
    zlbinfo :: Int64
    
    #Initilize Variables
    polyappnew = Array{Float64}(undef,2*poly.nfunc)  
    endogvar = Array{Float64}(undef,poly.nvars+poly.nexog,1)
    endogvarzlb = Array{Float64}(undef,poly.nvars+poly.nexog,1)
    endogvarp = Array{Float64}(undef,poly.nvars+poly.nexog,1)
    endogvarzlbp = Array{Float64}(undef,poly.nvars+poly.nexog,1)
    slopeconcont = Array{Float64}(undef,2*poly.nexogcont,1)
    xgridshock = Array{Float64}(undef,poly.nexogcont,1)
    slopeconxxmsv = Array{Float64}(undef,2*poly.nmsv,1)
    xgridmsv = Array{Float64}(undef,poly.nmsv,1)
    abserror = Array{Float64}(undef,2*poly.nfunc,1)
    ev = Array{Float64}(undef,12,1)
    exp_eul = Array{Float64}(undef,12,1)
    
    currentshockvalues=zeros(poly.nexog)
    polyapp=zeros(2*poly.nfunc,1)
    endogvarm1=zeros(poly.nvars+poly.nexog,1)
    exp_var = zeros(12)
    innovations = zeros(poly.nexog)

    nmsvplus = poly.nmsv+poly.nexogcont
    if (poly.nexogcont > 0)
        slopeconcont[1:poly.nexogcont] = slopeconxx[poly.nmsv+1:nmsvplus]
        slopeconcont[poly.nexogcont+1:2*poly.nexogcont] = slopeconxx[nmsvplus+poly.nmsv+1:2*nmsvplus]
        xgridshock = xgrid[poly.nmsv+1:nmsvplus,gridindex]
        currentshockvalues[poly.nexog-poly.nexogcont+1:poly.nexog] = msv2xx(xgridshock,poly.nexogcont,slopeconcont)
    end

    currentshockvalues[1:poly.nexogshock] = poly.exoggrid[1:poly.nexogshock,shockpos]
    shockpospoly = shockpos + poly.ns
    for ifunc in 1:poly.nfunc
        polyapp[ifunc] = dot(alphacoeff[(ifunc-1)*poly.ngrid+1:ifunc*poly.ngrid,shockpos],bbt[:,gridindex])
        polyapp[poly.nfunc+ifunc] = dot(alphacoeff[(ifunc-1)*poly.ngrid+1:ifunc*poly.ngrid,shockpospoly],bbt[:,gridindex])
    end

    xgridmsv = xgrid[1:poly.nmsv,gridindex]
    slopeconxxmsv[1:poly.nmsv] = slopeconxx[1:poly.nmsv]
    slopeconxxmsv[poly.nmsv+1:2*poly.nmsv] = slopeconxx[nmsvplus+1:nmsvplus+poly.nmsv]
    endogvarm1[1:poly.nmsv] = exp.( msv2xx(xgridmsv,poly.nmsv,slopeconxxmsv) )
    zlbintermediate = false  #force evaluation of 1 poly case at date t
    omegapoly = 1.0 #SET OMEGAPOLY TO 1 SINCE ZLBINTERMEDIATE IS FALSE
    llabss = poly.endogsteady[12]

    endogvar=intermediatedec(poly.nparams,poly.nvars,poly.nexog,poly.nfunc,
                    endogvarm1,currentshockvalues,params,polyapp[1:poly.nfunc],
                    llabss,omegapoly,polyapp[1:poly.nfunc],zlbintermediate)
                
    if ((zlbinfo != 0) & (poly.zlbswitch == true)) 
        endogvarzlb= intermediatedec(poly.nparams,poly.nvars,poly.nexog,poly.nfunc
                                ,endogvarm1,currentshockvalues,params,polyapp[poly.nfunc+1:2*poly.nfunc],
                                llabss,omegapoly,polyapp[poly.nfunc+1:2*poly.nfunc],zlbintermediate)
        endogvarzlb[9] = 1.0
    end
    rkss = params[3]/params[1]-1.0+params[16]

    for ss in 1:poly.nquad
        innovations[1:poly.nexogshock] = poly.ghnodes[:,ss] 
        if (poly.nexogcont > 0) 
            innovations[poly.nexog-poly.nexogcont+1:poly.nexog] =  poly.ghnodes[poly.nexogshock+1:poly.nexogshock+poly.nexogcont,ss] 
        end
        endogvarp=decr(endogvar,innovations,params,poly,alphacoeff) # NOT SURE WHAT TO DO WITH THIS
        techshkp = exp(endogvarp[25])
        invshkp = exp(endogvarp[24])
        ev[1] = endogvarp[10]/(endogvarp[6]*techshkp)

        utilcostp = (rkss/params[18])*(exp(params[18]*(endogvarp[13]-1.0))-1.0)
        ev[2] = (endogvarp[10]/techshkp)*( (endogvarp[15]*endogvarp[13])-utilcostp+(1.0-params[16])*endogvarp[11] )
        ev[3] = endogvarp[10]*(endogvarp[18]-1.0)*endogvarp[18]*endogvarp[7]
        ev[4] = (endogvarp[19]-1.0)*endogvarp[19] 
        ev[5] = endogvarp[16]/techshkp 
        ev[6] = endogvarp[10]*endogvarp[11]*invshkp*(endogvarp[17]-1.0)*endogvarp[17]*endogvarp[17]

        if ((zlbinfo != 0) & (poly.zlbswitch == true))
            endogvarzlbp=decr(endogvarzlb,innovations,params,poly,alphacoeff)
            ev[7] = endogvarzlbp[10]/(endogvarzlbp[6]*techshkp) 
            utilcostp = (rkss/params[18])*(exp(params[18]*(endogvarzlbp[13]-1.0))-1.0)
            ev[8] = (endogvarzlbp[10]/techshkp)*( (endogvarzlbp[15]*endogvarzlbp[13])-utilcostp+(1-params[16])*endogvarzlbp[11] )
            ev[9] = endogvarzlbp[10]*(endogvarzlbp[18]-1.0)*endogvarzlbp[18]*endogvarzlbp[7]
            ev[10] = (endogvarzlbp[19]-1.0)*endogvarzlbp[19] 
            ev[11] = endogvarzlbp[16]/techshkp 
            ev[12] = endogvarzlbp[10]*endogvarzlbp[11]*invshkp*(endogvarzlbp[17]-1.0)*endogvarzlbp[17]*endogvarzlbp[17]
        else
            ev[7:12] = ev[1:6]
        end
        exp_var = exp_var + poly.ghweights[ss]*ev   
    end

    
    
    liqshk = exp(endogvar[23])
    invshk = exp(endogvar[24])
    ep = params[9]
    exp_eul[1] =  (params[1]/params[3])*liqshk*endogvar[9]*exp_var[1]
    exp_eul[2] = (params[1]/params[3])*exp_var[2]/endogvar[10]
    exp_eul[3] =  params[1]*exp_var[3]/(endogvar[10]*endogvar[7])+(ep/params[7])*( endogvar[14]-(ep-1.0)/ep ) 
    exp_eul[4] = params[1]*exp_var[4]+(params[10]/params[8])*endogvar[10]*endogvar[12]*
           ( (params[4]*endogvar[12]^params[6]/endogvar[10])-((params[10]-1.0)/params[10])*endogvar[4] ) 
    exp_eul[5] = exp_var[5]
    exp_eul[6] = (params[1]/params[3])*exp_var[6]/endogvar[10] - 0.5*endogvar[11]*invshk*(endogvar[17]-1.0)*(endogvar[17]-1.0)

    polyappnew[1] = log(exp_eul[1])
    polyappnew[2] = log(exp_eul[2])
    polyappnew[3] = exp_eul[3]
    polyappnew[4] = exp_eul[4]
    polyappnew[5] = log(exp_eul[5])
    polyappnew[6] = exp_eul[6]
    polyappnew[7] = log( 1.0 + (1/params[18])*log(endogvar[15]/rkss) )

    if ((zlbinfo != 0) & (poly.zlbswitch == true))
        exp_eul[7] =  (params[1]/params[3])*liqshk*endogvarzlb[9]*exp_var[7]
        exp_eul[8] = (params[1]/params[3])*exp_var[8]/endogvarzlb[10]
        exp_eul[9] =  params[1]*exp_var[9]/(endogvarzlb[10]*endogvarzlb[7])+(ep/params[7])*( endogvarzlb[14]-(ep-1.0)/ep )
        exp_eul[10] = params[1]*exp_var[10]+(params[10]/params[8])*endogvarzlb[10]*endogvarzlb[12]*
           ( (params[4]*endogvarzlb[12]^params[6]/endogvarzlb[10])-((params[10]-1.0)/params[10])*endogvarzlb[4] ) 
        exp_eul[11] = exp_var[11]
        exp_eul[12] = (params[1]/params[3])*exp_var[12]/endogvarzlb[10] - 0.5*endogvarzlb[11]*invshk*(endogvarzlb[17]-1.0)*(endogvarzlb[17]-1.0)

        polyappnew[8] = log(exp_eul[7])
        polyappnew[9] = log(exp_eul[8])
        polyappnew[10] = exp_eul[9] 
        polyappnew[11] = exp_eul[10] 
        polyappnew[12] = log(exp_eul[11])
        polyappnew[13] = exp_eul[12]
        polyappnew[14] = log( 1.0 + (1/params[18])*log(endogvarzlb[15]/rkss) )
    else
        exp_eul[7:12] = exp_eul[1:6]
        polyappnew[8:14] = polyappnew[1:7]
    end

    errsum = 0.0
    errmax = 0.0
    imax = 0
                    
    for ifunc in 1:2*poly.nfunc
        abserror[ifunc] = abs(polyappnew[ifunc]-polyapp[ifunc])
        errsum = errsum + abserror[ifunc]
        if (abserror[ifunc] > errmax)
            errmax = abserror[ifunc]
            imax = copy(ifunc)
        end
    end
    #errsum = errsum/convert(Float64,(2*poly.nfunc))
    errsum = errsum/(2*poly.nfunc)
                            
    return polyappnew, errsum, errmax

end

               
function finite_grid(n,rho,sigmaep)

    #Input
    n :: Int64
    rho :: Float64     
    sigmaep :: Float64 
                
    #Initilize Variables
    shockgrid=zeros(n) 
    maxgridstd = 3.0

    nu = sqrt(1.0/(1.0-rho^2))*maxgridstd*sigmaep
    shockgrid[n]  = nu
    shockgrid[1]  = -1*shockgrid[n]
    zstep = (shockgrid[n] - shockgrid[1]) / (n - 1)

    for i in 2:n-1
        shockgrid[i] = shockgrid[1] + zstep * (i - 1)
    end 

    return zstep,shockgrid

end


function get_shockdetails(nparams,nexog,nexogshock,nexogcont,ns,number_shock_values,ngridshocks,params,exogvarinfo)

    #Input
    nparams :: Int64
    nexog :: Int64
    nexogshock :: Int64
    nexogcont :: Int64
    ns :: Int64
    number_shock_values :: Int64
    ngridshocks :: Array{Int64}
    exogvarinfo :: Array{Int64}
    params :: Array{Float64}
    
    #Initilize Variables  
    shockbounds = Array{Float64}(undef,nexogshock,2)
    shockdistance = Array{Float64}(undef,nexogshock,1)
    currentshockindex = Array{Float64}(undef,nexogshock,1)
    nshocksum_vec = Array{Float64}(undef,nexogshock,1)
    exoggrid = zeros(nexog-nexogcont,ns)
                
    sdevtech = params[24]
    rhog = params[25]
    sdevg = params[26]
    rhoinv = params[27]
    sdevinv = params[28]
    rholiq = params[29]
    sdevliq = params[30]
    rhoint = params[31]
    sdevint = params[32]
    rhoa = params[33]
    sdeva = params[34] 

    rhovec = [rholiq,rhoinv,0.0,rhoint,rhog,rhoa]
    sigmavec = [sdevliq,sdevinv,sdevtech,sdevint,sdevg,sdeva]

    nshocksum = 0
    shockvalues = zeros(number_shock_values)
                
    for i in 1:nexogshock
        xshock = Array{Float64}(undef,ngridshocks[i])
        shockdistance[i],xshock=finite_grid(ngridshocks[i],rhovec[i],sigmavec[i]) 
        shockbounds[i,1] = xshock[1]
        shockbounds[i,2] = xshock[ngridshocks[i]]
        shockvalues[nshocksum+1:nshocksum+ngridshocks[i]] = xshock
        nshocksum = nshocksum + ngridshocks[i]
    end

    for ss in 1:ns
        currentshockindex = exogvarinfo[:,ss]
        nshocksum_vec = zeros(Int64,nexogshock,1)
        nall = ngridshocks[1]
        shockpos = currentshockindex[1]
        exoggrid[1,ss] = shockvalues[currentshockindex[1]]
        for i in 2:nexogshock
            nshocksum_vec[i] = nshocksum_vec[i-1] + ngridshocks[i-1]
            shockpos = shockpos + nall*(currentshockindex[i]-1)
            nall = nall*ngridshocks[i]
            exoggrid[i,ss] = shockvalues[nshocksum_vec[i] + currentshockindex[i]]
        end
    end
                            
    return exoggrid,shockbounds,shockdistance

end

function calc_premium(endogvar,params,poly,alphacoeff)

    # Input
    poly :: polydetails
    params :: Array{Float64}
    endogvar :: Array{Float64}
    alphacoeff :: Array{Float64}

    # Initilize Variables
    endogvarp = Array{Float64}(undef,poly.nvars+poly.nexog,1)
    innovations=zeros(poly.nexog,1)

    rkss = params[3]/params[1]-1.0+params[16]

    exp_var = 0.0
    for ss in 1:poly.quad
        innovations[1:poly.exogshock] = poly.ghnodes[:,ss] 
        endogvarp=decr(endogvar,innovations,params,poly,alphacoeff)
        techshkp = exp(endogvarp[25])
        invshkp = exp(endogvarp[4])
        utilcostp = (rkss/params[18])*(exp(params[18]*(endogvarp[13]-1.0))-1.0)
        ev = ( (endogvarp[15]*endogvarp[13])-utilcostp+(1.0-params[16])*endogvarp[11] )*endogvarp[6]
        exp_var = exp_var + poly.ghweights[ss]*ev   
    end

    premium = exp_var/(endogvar[11]*endogvar[9])
            
    return premium

end


end 
