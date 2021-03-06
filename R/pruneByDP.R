#' Exact segmentation of a multivariate signal using dynamic programming.
#' 
#' Exact segmentation of a multivariate signal using dynamic programming.
#' 
#' This function retrieves the maximum likelihood solution of the gaussian
#' homoscedastic change model into segments, for \eqn{K \in {1 \dots
#' length(candCP)}}. The dynamic programming algorithm used is quadratic in
#' time. For signals containing more than 1000 points, we recommend using a
#' first pass segmentation (see \code{\link{segmentByRBS}}) to find a smaller
#' number of candidates, and to run \code{pruneByDP} on these candidates only,
#' as initially suggested by Gey and Lebarbier (2008). These two steps can be
#' performed using \code{\link{jointSeg}} for generic multivariate signals, and
#' using \code{\link{PSSeg}} for copy number signals from SNP array data.
#' 
#' if \code{allowNA}, the calulation of the cost of removing candidate
#' breakpoints between i and j for i<j tolerates missing values. Method
#' \code{!allowNA} is maintained in order to check consistency with the
#' original dynamic programming in the absence of NA:s.
#' 
#' @param Y A \code{n*p} signal to be segmented
#' @param candCP A vector of candidate change point positions (defaults to
#' 1:(n-1))
#' @param K The maximum number of change points to find
#' @param allowNA A boolean value specifying whether missing values should be
#' allowed or not.
#' @param verbose A \code{logical} value: should extra information be output ?
#' Defaults to \code{FALSE}.
#' @return A list with elements: \item{bkpList}{A list of vectors of change
#' point positions for the best model with k change points, for k=1, 2, ... K}
#' \item{rse}{A vector of K+1 residual squared errors} \item{V}{V[i,j] is the
#' best RSE for segmenting intervals 1 to j }
#' @note This implementation is derived from the MATLAB code by Vert and
#' Bleakley: \url{http://cbio.ensmp.fr/GFLseg}.
#' @author Morgane Pierre-Jean and Pierre Neuvial
#' @seealso \code{\link{jointSeg}}, \code{\link{PSSeg}}
#' @references Bellman, R. (1961). On the approximation of curves by line
#' segments using dynamic programming. Communications of the ACM, 4(6), 284.
#' 
#' Gey, S., & Lebarbier, E. (2008). Using CART to Detect Multiple Change Points
#' in the Mean for Large Sample. http://hal.archives-ouvertes.fr/hal-00327146/
#' @examples
#' 
#' p <- 2
#' trueK <- 10
#' sim <- randomProfile(1e4, trueK, 1, p)
#' Y <- sim$profile
#' K <- 2*trueK
#' res <- segmentByRBS(Y, K)
#' resP <- pruneByDP(Y, res$bkp)
#' 
#' ##   Note that all of the above can be dmethod=="other"one directly using 'jointSeg'
#' resJ <- jointSeg(sim$profile, method="RBS", K=K)
#' stopifnot(identical(resP$bkpList, resJ$dpBkp))
#' 
#' ## check consistency when no NA
#' resP2 <- pruneByDP(Y, res$bkp, allowNA=FALSE)
#' max(abs(resP$rse-resP2$rse))
#' 
#' plotSeg(Y, list(resP$bkp[[trueK]], sim$bkp), col=1)
#' 
#' @export pruneByDP
pruneByDP <- function(Y, candCP=1:(nrow(Y)-1), K=length(candCP), allowNA=TRUE, verbose=FALSE){
    ## Argument 'Y'
    if (is.null(dim(Y)) || is.data.frame(Y)) {
        if (verbose) {
            print("Coercing 'Y' to a matrix")
        }
        Y <- as.matrix(Y)
    } else if (!is.matrix(Y)){
        stop("Argument 'Y' should be a matrix, vector or data.frame")
    }
    n <- nrow(Y)
    p <- ncol(Y)
    if (K*length(candCP)^2>1e9) {
        cat("Please note that 'pruneByDP' is intended to be run on a not too large set of *candidate* change points.  Running it on too many candidates can be long, as the algorithm is quadratic in the number of candidates\n")
    }
    ## Argument 'candCP'
    if (length(candCP)) {
        rg <- range(candCP);
        stopifnot(rg[1]>=1 && rg[2]<=n)
    }

    ## Compute boundaries of the smallest intervals considered
    b <- as.integer(sort(c(0, candCP, n)))
    k <- length(candCP) + 1 # number of such intervals
    
    ## Compute the k*k matrix J such that J[i,j] for i<=j is the RSE
    ## when intervals i to j are merged
    J <- matrix(numeric(k*k), ncol=k)
    if (allowNA) {
        for (pp in 1:p) {
            Jpp <- getUnivJ(Y[, pp], candCP)
            Jpp[is.nan(Jpp)] <- 0  ## happens when all values are NA between two successive candidates
            ## then the corresponding dimension contributes 0 (ie no cost/gain of merging)
            J <- J + Jpp
        }
    } else {
        s <- rbind(rep(0,p), apply(Y, 2, cumsum))
        v <- c(0, cumsum(rowSums(Y^2)))
        for (ii in 1:k) {
            Istart <- b[ii] +1
            for(jj in ii:k){
                Iend <- b[jj+1]
                J[ii,jj] <- v[Iend+1] - v[Istart] - sum((s[Iend+1,]-s[Istart,])^2)/(Iend-Istart+1)
            }
        } ## for (ii ...
    } ## if (!allowNA)
    
    ## Dynamic programming
    V <- matrix(numeric((K+1)*k), ncol = k)
    ## V[i,j] is the best RSE for segmenting intervals 1 to j
    ## with at most i-1 change points
    bkp <-   matrix(integer(K*k), ncol = k)
    ## With no change points, V[i,j] is juste the precomputed RSE
    ## for intervals 1 to j
    V[1, ] <- J[1, ]
    KK <- seq(length=K)
    ## Then we apply the recursive formula
    for (ki in KK){
        for (jj in (ki+seq(length=k-ki))){
            obj <- V[ki,ki:(jj-1)] + J[(ki+1):jj, jj]
            val <- min(obj)
            ind <- which.min(obj)
            V[ki+1, jj] <- val
            bkp[ki, jj] <- ind + ki-1L
        }
    }
    
    ## Optimal segmentation
    res.bkp <- list()
    for (ki in KK){
        res.bkp[[ki]] <- integer(ki)
        res.bkp[[ki]][ki] <- bkp[ki, k]
        if (ki!=1) {
            for (ii in (ki-seq(length=ki-1))) {
                res.bkp[[ki]][ii] <- bkp[ii, res.bkp[[ki]][ii+1]]
            }
        }
    }
    ## Convert back the index of the interval to the last position before the bkp
    rightlimit <- b[2:length(b)]
    for(ki in KK) {
        res.bkp[[ki]] <- rightlimit[res.bkp[[ki]]]
    }
    ## RSE as a function of number of change-points
    res.rse <- V[, k]
    ## Optimal number of change points
    ##  options(warn=-1) ## warnings can be useful

    list(bkpList=res.bkp, 
         rse=res.rse, 
         V=V) 
}


############################################################################
## HISTORY:
## 2013-04-10
## o Added argument 'K'.
## 2013-01-09
## o Replace all jumps by bkp
## 2012-12-31
## o Added boolean argument 'allowNA' to handle missing values (NA:s).
## 2012-12-30
## o Added example.
## o Added safeguards for extreme case (e.g. candCP==NULL).
## 2012-12-27
## o Renamed argument candidatechangepoints to candCP.
## o Renamed to pruneByDP.
## o Some code and doc cleanups.
## 2012-11-27
## o Moved model selection part to 'modelSelection'.
## 2012-09-13
## o Some code cleanups.
## 2012-08-21
## o Created.
############################################################################

