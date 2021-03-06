include("simulate_model.jl")

module class_model
    using DelimitedFiles

    import Main.polydef: polydetails, linsoldetails, solutiondetails,initializesolution!, initializelinearsolution!
    import Main.model_details: decr, model_details_ss
    import Main.get_decisionrule: nonlinearsolver
    import Main.simulate_model: simulate_data, simulate_irfs
    export model, load_data!, describe!, new_model, describe_params!, solve_serial, simulate_modeldata

mutable struct model
    
    name :: String #"ghlss_v5_2"
    datafile :: String # "data/glss_data.txt"
    
    nobs:: Int64 #7 no way to initilize some values and uninitilize others from what I can tell
    T :: Int64 #125
    neps :: Int64 #6
    
    yy :: Array{Float64}
    HH :: Array{Float64}

    solution :: solutiondetails #Had to include thses structs in this file to get this struct to work, will not allow structs to be loaded ...
    params :: Array{Float64}

    npara :: Int64
    nvars :: Int64
    nexog :: Int64
    
    model()=new()

end

function load_data!(m)

    m :: model
    m.yy = readdlm(m.datafile) # I think this way will work best
    
    return

end 

function describe!(m)

    m :: model

    println( "- - - - - - - - - - - - ")
    println("Model Name: ", m.name)
    println("number of parameters: ", m.solution.poly.nparams)
    println("number of potential shocks = ", m.solution.poly.nexog)
    println("number of active shocks = ", m.solution.poly.nexogshock+m.solution.poly.nexogcont)
    println("number of shocks in polynomial = ", m.solution.poly.nexogcont)
    println("number of grid points used for finite-element part of decr = ", m.solution.poly.ns)
    println("number of grid points used for poly part of decr = ", m.solution.poly.ngrid)
    println("number of quadrature points = ", m.solution.poly.nquad)
    println("- - - - - - - - - - - - ")
    
    return
  
end

function describe_params!(m)

    m :: model

    println("model Name: ", m.name)
    println("number of parameters: ", m.solution.poly.nparams)

    println("- - - - - - - - - - - - ")
    for i in 1:m.solution.poly.nparams 
        println("m%params[',i,'] = ", m.params[i])
    end
    println("---------------------------------")
    
    return 
    
end


function new_model(zlbswitch,inputfile="data/glss_data.txt")
    
    #input variables
    zlbswitch :: Bool
    inputfile :: String
    
    #Input user based parameters of the solution
    m=model()
    m.solution = solutiondetails()
    m.solution.poly = polydetails() #Must initilize subtype
    m.solution.linsol = linsoldetails()
    
    #zlbswitch
    m.solution.poly.zlbswitch = zlbswitch
    if (zlbswitch == false)
        m.name = "ghlss_v5_2_unc"
    else
        m.name= "ghlss_v5_2"
    end
        
    #initilize model parameters
    m.nobs=7
    m.T=125
    m.neps=6
    m.datafile=inputfile
        
    #Initilize solution parameters
    m.solution.poly.nparams = 43
    m.solution.poly.nexog = 6
    m.solution.poly.nexogcont = 0 
    #m.solution.poly.nexogcont = 1  #adds level technology shock into polynomial 
    m.solution.poly.nvars = 22
    m.solution.poly.nmsv = 7
    m.solution.poly.nfunc = 7
    m.solution.poly.nindplus = 1

    # number of grid points : shock to safe assets, MEI, tech, r shock, g shock, technology
    #m.solution.poly.nshockgrid=[7 3 3 3 3 1]
    m.solution.poly.nshockgrid=[7 2 2 2 2 1]

    npara = m.solution.poly.nparams
    nvars = m.solution.poly.nvars+m.solution.poly.nexog
    nexog = m.solution.poly.nexog

    if (m.solution.poly.nindplus == 1) 
        m.solution.poly.indplus = Array{Int64}(undef,m.solution.poly.nindplus,1)
        m.solution.poly.indplus[1] = 3
    end

    m.solution.poly.zlbswitch = false #zlbswitch

    #Initilize values for the solution
    initializesolution!(m.solution)
        
    #Allocates space and loads data
    m.yy = Array{Float64}(undef,m.nobs,m.T)
    m.HH = Array{Float64}(undef,m.nobs,m.nobs)
    load_data!(m)
        
    return m

end

function solve_serial(m, params) 
    
    #Input
    m :: model
    params :: Array{Float64}

    m.solution, convergence=nonlinearsolver(params, m.solution) 
    m.params = params
    
    return m.solution, convergence #MAY NEED TO ADJUST THE IN/OUT OF THIS FUNCTION
end 

function steadystate(self, params) 

    #Input
    self :: model
    params :: Array{Float64}
    ss = zeros(self.nvars)

    #Solve for steady state
    ss = model_details_ss(params,self.nvars,self.npara) 

    for i in 1:self.nvars
        if (i <= self.solution.poly.nmsv) 
            ss[i] = exp(ss[i])
        else 
            ss[i] = ss[i]
        end
    end

    return ss

end 

function simulate_modeldata(m,capt,nonlinearswitch,seed)
     
    #Input
    m :: model
    capt :: Int64
    nonlinearswitch :: Bool
    seed :: Int64
    
    #Initilize variables
    modeldata = Array{Float64}(undef,m.solution.poly.nvars+2*m.solution.poly.nexog,capt)
  
    modeldata = simulate_data(capt,m.params,m.solution.poly,m.solution.linsol,m.solution.alphacoeff,nonlinearswitch,seed) # NEED TO ADD THIS FUNCTION
    
    return modeldata
  
end

function simulate_modelirfs(m,capt,nsim,shockindex,neulererrors)

    # Input
    m :: model
    capt :: Int64
    nsim :: Int64
    shockindex :: Int64
    neulererrors :: Int64
    
    # Initilize variables
    endogirf = Array{Float64}(undef,m.solution.poly.nvars+m.solution.poly.nexog+2,capt)
    linirf = Array{Float64}(undef,m.solution.poly.nvars+m.solution.poly.nexog+2,capt)
    euler_errors = Array{Float64}(undef,2*neulererrors,capt)
    endogvarshk0 = Array{Float64}(undef,m.solution.poly.nvars+m.solution.poly.nexog)
    premiumirf = Array{Float64}(undef,2,capt)
    innov0 = zeros(m.solution.poly.nexog,1)
    endogvarbas0 = zeros(m.solution.poly.nvars+m.solution.poly.nexog)
  
    endogvarbas0[1:m.solution.poly.nvars] = exp(m.solution.poly.endogsteady[1:m.solution.poly.nvars])
    endogvarshk0 = copy(endogvarbas0)

    #shock to liquidity    
    if (shockindex == 1)
        scaleshock = 1.0
        endogvarshk0[m.solution.poly.nvars+shockindex] = scaleshock*m.params[30]/(1.0-m.params[29]^2)    
    end

    #shock to MEI
    if (shockindex == 2)
        scaleshock = -1.0
        endogvarshk0[m.solution.poly.nvars+shockindex] = scaleshock*m.params[28]/(1.0-m.params[27]^2)      
    end
    endogvarbas0 = copy(endogvarshk0)  #change initial conditions of shock and baseline dset
    innov0[shockindex] = scaleshock

    endogirf,linirf,euler_errors,premirf = simulate_irfs(capt,nsim,m.params,m.solution.poly,m.solution.alphacoeff,m.solution.linsol,endogvarbas0,
                    endogvarshk0,innov0,endogirf,linirf,euler_errors,neulererrors,premiumirf)
   
    return endogirf,linirf,euler_errors
end

end
