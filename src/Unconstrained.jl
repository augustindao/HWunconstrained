

module Unconstrained

	# imports: which packages are we going to use in this module?
	using Distributions, Optim, PyPlot, DataFrames

	"""
    `input(prompt::AbstractString="")`
  
    Read a string from STDIN. The trailing newline is stripped.
  
    The prompt string, if given, is printed to standard output without a
    trailing newline before reading input.
    """
    function input(prompt::AbstractString="")
        print(prompt)
        return chomp(readline())
    end

    export maximize_like_grad, runAll, makeData



	# methods/functions
	# -----------------

	# data creator
	# should/could return a dict with beta,numobs,X,y,norm)
	# true coeff vector, number of obs, data matrix X, response vector y, and a type of parametric distribution for G.
	function makeData(n=10000)
		beta = [ 1; 1.5; -0.5 ]
		srand(3122015)
		numobs = n
		X = randn(numobs,3)    # n,k
		# X = hcat(ones(numobs), randn(numobs,2))    # n,k
		epsilon = randn(numobs)
		Y = X * beta + epsilon
		y = 1.0 * (Y .> 0)
		norm = Normal(0,1)	# create a normal distribution object with mean 0 and variance 1
		return Dict("beta"=>beta,"n"=>numobs,"X"=>X,"y"=>y,"dist"=>norm)
	end


	# log likelihood function at x
	# function loglik(betas::Vector,X::Matrix,y::Vector,distrib::UnivariateDistribution) 
	function loglik(betas::Vector,d::Dict)
		xbeta     = d["X"]*betas	# (n,1)
		G_xbeta   = cdf(d["dist"],xbeta)	# (n,1)
		loglike   = d["y"] .* log(G_xbeta) .+ (1-d["y"]) .* log(1-G_xbeta)  # (n,1)
		objective = -sum(loglike)
		return objective

	end

	# gradient of the likelihood at x
	function grad!(betas::Vector,storage::Vector,d)
		xbeta     = d["X"]*betas	# (n,1)
		G_xbeta   = cdf(d["dist"],xbeta)	# (n,1)
		g_xbeta   = pdf(d["dist"],xbeta)	# (n,1)
		storage[:]= -sum((d["y"] .* g_xbeta ./ G_xbeta - (1-d["y"]) .* g_xbeta ./ (1-G_xbeta)) .* d["X"],1)
		return nothing
	end

	# hessian of the likelihood at x
	function hessian!(betas::Vector,storage::Matrix,d)
		xbeta     = d["X"]*betas	# (n,1)
		G_xbeta   = cdf(d["dist"],xbeta)	# (n,1)
		g_xbeta   = pdf(d["dist"],xbeta)	# (n,1)
		xb1 = xbeta .* g_xbeta ./ G_xbeta .+ (g_xbeta ./ G_xbeta).^2
		xb0 = (g_xbeta ./ (1 .- G_xbeta)).^2  .- xbeta .* g_xbeta ./ (1 -G_xbeta) 
		fill!(storage,0.0)

		y1 = similar(storage)
		y0 = similar(storage)
		
		for i in 1:d["n"]
			XX = d["X"][i,:]' * d["X"][i,:]   #k,k
			if d["y"][i] == 1
				y1 = y1 .+ xb1[i] * XX
			else
				y0 = y0 .+ xb0[i] * XX
			end
		end
		storage[:,:] = y0 .+ y1
		return nothing
	end


	"""
	inverse of observed information matrix
	"""
	function inv_observedInfo(betas::Vector,d)
		h = zeros(length(betas),length(betas))
		hessian!(betas,h,d)
		inv(h)
	end

	"""
	standard errors
	"""
	function se(betas::Vector,d::Dict)
		sqrt(diag(inv_observedInfo(betas,d)))
	end

	# function that maximizes the log likelihood without the gradient
	# with a call to `optimize` and returns the result
	function maximize_like(x0=[0.8,1.0,-0.1];meth=NelderMead())
		d = makeData(10000)
		res = optimize(arg->loglik(arg,d),x0, meth, Optim.Options(iterations = 100))
		return res
	end



	# function that maximizes the log likelihood with the gradient
	# with a call to `optimize` and returns the result
	function maximize_like_grad(x0=[0.8,1.0,-0.1];meth=BFGS())
		d = makeData(10000)
		# storage = zeros(length(d["beta"]))
		res = optimize((arg)->loglik(arg,d),(arg,g)->grad!(arg,g,d),x0,meth, Optim.Options(iterations = 1000,g_tol=1e-6,f_tol=1e-20))
		return res
	end

	function maximize_like_grad_hess(x0=[0.8,1.0,-0.1];meth=Newton())
		d = makeData(10000)
		# storage = zeros(length(d["beta"]))
		res = optimize((arg)->loglik(arg,d),(arg,g)->grad!(arg,g,d),(arg,g)->hessian!(arg,g,d),x0, meth, Optim.Options(iterations = 1000,g_tol=1e-20,f_tol=1e-20))
		return res
	end

	function maximize_like_grad_se(x0=[0.8,1.0,-0.1];meth=BFGS())
		d = makeData(10000)
		# storage = zeros(length(d["beta"]))
		res = optimize((arg)->loglik(arg,d),(arg,g)->grad!(arg,g,d),x0, meth, Optim.Options(iterations = 1000,g_tol=1e-20,f_tol=1e-20))
		ses = se(res.minimizer,d)
		return DataFrame(Parameter=["beta$i" for i=1:length(x0)], Estimate=res.minimizer, StandardError=ses)
	end


	# visual diagnostics
	# ------------------

	# function that plots the likelihood
	# we are looking for a figure with 3 subplots, where each subplot
	# varies one of the parameters, holding the others fixed at the true value
	# we want to see whether there is a global minimum of the likelihood at the the true value.
	function plotLike()
		d = makeData(10000)
		ngrid = 100
		pad = 1
		k = length(d["beta"])
		beta0 = repmat(d["beta"]',ngrid,1)
		values = zeros(ngrid)
		fig,axes = subplots(1,k)
		currplot = 0
		for b in 1:k
			currplot += 1
			xaxis = collect(linspace(d["beta"][b]-pad,d["beta"][b]+pad,ngrid))
			betas = copy(beta0)
			betas[:,b] = xaxis
			for i in 1:ngrid
				values[i] = loglik(betas[i,:][:],d)
			end
			ax = axes[currplot]
			ax[:plot](xaxis,values)
			ax[:set_title]("beta $currplot")
			ax[:axvline](x=d["beta"][b],color="red")

		end
		fig[:canvas][:draw]()
		fig[:canvas][:set_window_title]("Objective Function Plot")
	end
	function plotGrad()
		d = makeData(10000)
		ngrid = 100
		pad = 1
		k = length(d["beta"])
		beta0 = repmat(d["beta"]',ngrid,1)
		values = zeros(ngrid,k)
		grad = ones(k)
		fig,axes = subplots(1,k)
		currplot = 0
		for b in 1:k
			currplot += 1
			xaxis = collect(linspace(d["beta"][b]-pad,d["beta"][b]+pad,ngrid))
			betas = copy(beta0)
			betas[:,b] = xaxis
			for i in 1:ngrid
				grad!(betas[i,:][:],grad,d)
				values[i,:] = grad
			end
			ax = axes[currplot]
			ax[:plot](xaxis,values)
			ax[:set_title]("beta $currplot")
			ax[:axvline](x=d["beta"][b],color="red")

		end
		fig[:canvas][:draw]()
		fig[:canvas][:set_window_title]("Gradient Plot")
	end

	"""
	Version for two separate functions supplying objective and gradient
	"""
	function test_finite_diff(f::Function,g::Vector{Float64},x::Vector{Float64},tol=1e-6)
		# get gradient from f
		grad = g
		# get finite difference approx
		fdiff = finite_diff2(f,x)
		r = hcat(1:length(x),grad,fdiff,abs(grad-fdiff))
		errors = find(abs(grad-fdiff).>tol)
		if length(errors) >0
			println("elements with errors:")
			println("id  supplied gradient     finite difference     abs diff")
			for i in 1:length(errors)
				@printf("%d   %f3.8            %f3.8          %f1.8\n",r[errors[i],1],r[i,2],r[i,3],r[i,4])
			end
			return (false,errors)
		else 
			println("no errors.")
			return true
		end
	end
	function finite_diff2(f::Function,x::Vector)
		h = sqrt(eps())
		fgrad = similar(x)
		tgrad = similar(x)
		for i in 1:length(x)
			step = abs(x[i]) > 1 ? abs(x[i]) * h : 1.0 * h
			newx = copy(x)
			newx[i] = x[i]+step
			fgrad[i] = (f(newx) - f(x))/step
		end
		return fgrad
	end

	function runAll()

		# plotLike()
		m1 = maximize_like()
		m2 = maximize_like_grad()
		m3 = maximize_like_grad_hess()
		# m4 = maximize_like_grad_se()
		println("results are:")
		println("maximize_like: $(m1.minimizer)")
		println("maximize_like_grad: $(m2.minimizer)")
		println("maximize_like_grad_hess: $(m3.minimizer)")
		# println("maximize_like_grad_se: $m4")
		println("")
		println("running tests:")
		include("test/runtests.jl")
		println("")
		ok = input("enter y to close this session.")
		if ok == "y"
			quit()
		end
	end


end





