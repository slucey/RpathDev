################################################################################
# R version of ecosim (to work with ecosim.dll c code) by Kerim Aydin
#
# Version 0.04
################################################################################ 

##------------------------------------------------------------------------------ 
#Load and unload dll (unloading needed before compiling any c-code changes)
#Load
ll <- function() if(!is.loaded("ecosim_run")) dyn.load("ecosim.dll")

#Reload
rl<-function(){
  if(is.loaded("ecosim_run")) dyn.unload("ecosim.dll") 
  dyn.load("ecosim.dll")		
}

#Unload
ul<-function() if(is.loaded("ecosim_run")) dyn.unload("ecosim.dll") 	

##------------------------------------------------------------------------------ 

##------------------------------------------------------------------------------ 
#New ecosim function that runs all steps.
ecosim_init <- function(Rpath, juvfile, YEARS = 100){
  #Old path_to_rates--------------------------------------------------------------------
  MSCRAMBLE      <- 2.0
  MHANDLE        <- 1000.0
  PREYSWITCH     <- 1.0
  # For SelfWts 1.0 = no overlap, 0.0 = complete overlap
  ScrambleSelfWt <- 1.0
  HandleSelfWt   <- 1.0

  simpar <- c()
  
  simpar$NUM_GROUPS <- Rpath$NUM_GROUPS
  simpar$NUM_LIVING <- Rpath$NUM_LIVING
  simpar$NUM_DEAD   <- Rpath$NUM_DEAD
  simpar$NUM_GEARS  <- Rpath$NUM_GEARS
  
  simpar$spname     <- c("Outside", Rpath$Group)
  simpar$spnum      <- 0:length(Rpath$BB) 

  #Energetics for Living and Dead Groups
  #Reference biomass for calculating YY
  simpar$B_BaseRef <- c(1.0, Rpath$BB) 
  #Mzero proportional to (1-EE)
  simpar$MzeroMort <- c(0.0, Rpath$PB * (1.0 - Rpath$EE)) 
  #Unassimilated is the proportion of CONSUMPTION that goes to detritus.  
  simpar$UnassimRespFrac <- c(0.0, Rpath$GS);
  #Active respiration is proportion of CONSUMPTION that goes to "heat"
  #Passive respiration/ VonB adjustment is left out here
  simpar$ActiveRespFrac <-  c(0.0, ifelse(Rpath$QB > 0, 
                                        1.0 - (Rpath$PB / Rpath$QB) - Rpath$GS, 
                                        0.0))
  #Ftime related parameters
  simpar$FtimeAdj   <- rep(0.0, length(simpar$B_BaseRef))
  simpar$FtimeQBOpt <-   c(1.0, Rpath$QB)
  simpar$PBopt      <-   c(1.0, Rpath$PB)           

  #Fishing Effort defaults to 0 for non-gear, 1 for gear
  simpar$fish_Effort <- ifelse(simpar$spnum <= simpar$NUM_LIVING + simpar$NUM_DEAD,
                             0.0,
                             1.0) 
    
  #NoIntegrate
  STEPS_PER_YEAR  <- 12
  STEPS_PER_MONTH <- 1
  simpar$NoIntegrate <- ifelse(c(0, Rpath$PB) / 
                               (1.0 - simpar$ActiveRespFrac - simpar$UnassimRespFrac) > 
                               2 * STEPS_PER_YEAR * STEPS_PER_MONTH, 
                             0, 
                             simpar$spnum)  

  #Pred/Prey defaults
  simpar$HandleSelf   <- rep(HandleSelfWt,   Rpath$NUM_GROUPS + 1)
  simpar$ScrambleSelf <- rep(ScrambleSelfWt, Rpath$NUM_GROUPS + 1)
  
  #primary production links
  #primTo   <- ifelse(Rpath$PB>0 & Rpath$QB<=0, 1:length(Rpath$PB),0 )
  primTo   <- ifelse(Rpath$type == 1, 
                     1:length(Rpath$PB),
                     0)
  primFrom <- rep(0, length(Rpath$PB))
  primQ    <- Rpath$PB * Rpath$BB 
  
  #Predator/prey links
  preyfrom  <- row(Rpath$DC)
  preyto    <- col(Rpath$DC)	
  predpreyQ <- Rpath$DC * t(matrix(Rpath$QB[1:Rpath$NUM_LIVING] * Rpath$BB[1:Rpath$NUM_LIVING],
                           Rpath$NUM_LIVING, Rpath$NUM_LIVING + Rpath$NUM_DEAD))

  #combined
  simpar$PreyFrom <- c(primFrom[primTo > 0], preyfrom [predpreyQ > 0])
  simpar$PreyTo   <- c(primTo  [primTo > 0], preyto   [predpreyQ > 0])
  simpar$QQ       <- c(primQ   [primTo > 0], predpreyQ[predpreyQ > 0])             	
  
  numpredprey <- length(simpar$QQ)

  simpar$DD <- rep(MHANDLE,   numpredprey)
  simpar$VV <- rep(MSCRAMBLE, numpredprey)

  #NOTE:  Original in C didn't set handleswitch for primary production groups.  Error?
  #probably not when group 0 biomass doesn't change from 1.
  simpar$HandleSwitch <- rep(PREYSWITCH, numpredprey)

  #scramble combined prey pools
  Btmp <- simpar$B_BaseRef
  py   <- simpar$PreyFrom + 1.0
  pd   <- simpar$PreyTo + 1.0
  VV   <- simpar$VV * simpar$QQ / Btmp[py]
  AA   <- (2.0 * simpar$QQ * VV) / (VV * Btmp[pd] * Btmp[py] - simpar$QQ * Btmp[pd])
  simpar$PredPredWeight <- AA * Btmp[pd] 
  simpar$PreyPreyWeight <- AA * Btmp[py] 

  simpar$PredTotWeight <- rep(0, length(simpar$B_BaseRef))
  simpar$PreyTotWeight <- rep(0, length(simpar$B_BaseRef))
  
  for(links in 1:numpredprey){
    simpar$PredTotWeight[py[links]] <- simpar$PredTotWeight[py[links]] + simpar$PredPredWeight[links]
    simpar$PreyTotWeight[pd[links]] <- simpar$PreyTotWeight[pd[links]] + simpar$PreyPreyWeight[links]    
  }  
  #simpar$PredTotWeight[]   <- as.numeric(tapply(simpar$PredPredWeight,py,sum))
  #simpar$PreyTotWeight[]   <- as.numeric(tapply(simpar$PreyPreyWeight,pd,sum))

  simpar$PredPredWeight <- simpar$PredPredWeight/simpar$PredTotWeight[py]
  simpar$PreyPreyWeight <- simpar$PreyPreyWeight/simpar$PreyTotWeight[pd]

  simpar$NumPredPreyLinks <- numpredprey
  simpar$PreyFrom       <- c(0, simpar$PreyFrom)
  simpar$PreyTo         <- c(0, simpar$PreyTo)
  simpar$QQ             <- c(0, simpar$QQ)
  simpar$DD             <- c(0, simpar$DD)
  simpar$VV             <- c(0, simpar$VV) 
  simpar$HandleSwitch   <- c(0, simpar$HandleSwitch) 
  simpar$PredPredWeight <- c(0, simpar$PredPredWeight)
  simpar$PreyPreyWeight <- c(0, simpar$PreyPreyWeight)
  
  #catchlinks
  fishfrom    <- row(Rpath$Catch)                      
  fishthrough <- col(Rpath$Catch) + (Rpath$NUM_LIVING + Rpath$NUM_DEAD)
  fishcatch   <- Rpath$Catch
  fishto      <- fishfrom * 0
  
  if(sum(fishcatch) > 0){
    simpar$FishFrom    <- fishfrom   [fishcatch > 0]
    simpar$FishThrough <- fishthrough[fishcatch > 0]
    simpar$FishQ       <- fishcatch  [fishcatch > 0] / simpar$B_BaseRef[simpar$FishFrom + 1]  
    simpar$FishTo      <- fishto     [fishcatch > 0]
  }
  #discard links
  
  for(d in 1:Rpath$NUM_DEAD){
    detfate <- Rpath$DetFate[(Rpath$NUM_LIVING + Rpath$NUM_DEAD + 1):Rpath$NUM_GROUPS, d]
    detmat  <- t(matrix(detfate, Rpath$NUM_GEAR, Rpath$NUM_GROUPS))
   
    fishfrom    <-  row(Rpath$Discards)                      
    fishthrough <-  col(Rpath$Discards) + (Rpath$NUM_LIVING + Rpath$NUM_DEAD)
    fishto      <-  t(matrix(Rpath$NUM_LIVING + d, Rpath$NUM_GEAR, Rpath$NUM_GROUPS))
    fishcatch   <-  Rpath$Discards * detmat
    if(sum(fishcatch) > 0){
      simpar$FishFrom    <- c(simpar$FishFrom,    fishfrom   [fishcatch > 0])
      simpar$FishThrough <- c(simpar$FishThrough, fishthrough[fishcatch > 0])
      ffrom <- fishfrom[fishcatch > 0]
      simpar$FishQ       <- c(simpar$FishQ,  fishcatch[fishcatch > 0] / simpar$B_BaseRef[ffrom + 1])  
      simpar$FishTo      <- c(simpar$FishTo, fishto   [fishcatch > 0])
   }
  } 
  
  simpar$NumFishingLinks <- length(simpar$FishFrom)  
  simpar$FishFrom        <- c(0, simpar$FishFrom)
  simpar$FishThrough     <- c(0, simpar$FishThrough)
  simpar$FishQ           <- c(0, simpar$FishQ)  
  simpar$FishTo          <- c(0, simpar$FishTo)   

# Unwound discard fate for living groups
  detfrac <- Rpath$DetFate[1:(Rpath$NUM_LIVING + Rpath$NUM_DEAD), ]
  detfrom <- row(detfrac)
  detto   <- col(detfrac) + Rpath$NUM_LIVING
  
  detout <- 1 - rowSums(Rpath$DetFate[1:(Rpath$NUM_LIVING + Rpath$NUM_DEAD), ])
  dofrom <- 1:length(detout)
  doto   <- rep(0, length(detout))
  
  simpar$DetFrac <- c(0, detfrac[detfrac > 0], detout[detout > 0])
  simpar$DetFrom <- c(0, detfrom[detfrac > 0], dofrom[detout > 0])
  simpar$DetTo   <- c(0, detto  [detfrac > 0], doto  [detout > 0])
  
  simpar$NumDetLinks <- length(simpar$DetFrac) - 1

  simpar$state_BB    <- simpar$B_BaseRef
  simpar$state_Ftime <- rep(1, length(Rpath$BB) + 1)
  
  #Old initialize_stanzas------------------------------------------------------------------------
  #Initialize juvenile adult or "stanza" age structure in sim   
  MAX_MONTHS_STANZA <- 400
  MIN_REC_FACTOR    <- 6.906754779  #// This is ln(1/0.001 - 1) used to set min. logistic matuirty to 0.001

  juv        <- read.csv(juvfile)
  simpar$juv_N <- length(juv$JuvNum) 
    
  #fill monthly vectors for each species, rel weight and consumption at age
  #Loops for weight and numbers
  simpar$WageS      <- matrix(0,MAX_MONTHS_STANZA+1,simpar$juv_N+1)
  simpar$WWa        <- matrix(0,MAX_MONTHS_STANZA+1,simpar$juv_N+1)
  simpar$NageS      <- matrix(0,MAX_MONTHS_STANZA+1,simpar$juv_N+1)
  simpar$SplitAlpha <- matrix(0,MAX_MONTHS_STANZA+1,simpar$juv_N+1)

  simpar$state_NN       <-rep(0.0, simpar$NUM_GROUPS + 1)
  simpar$stanzaPred     <-rep(0.0, simpar$NUM_GROUPS + 1)
  simpar$stanzaBasePred <-rep(0.0, simpar$NUM_GROUPS + 1)

  simpar$SpawnBio       <- rep(0.0, simpar$juv_N + 1)
  simpar$EggsStanza     <- rep(0.0, simpar$juv_N + 1)
  simpar$stanzaGGJuv    <- rep(0.0, simpar$juv_N + 1)
  simpar$stanzaGGAdu    <- rep(0.0, simpar$juv_N + 1)
  #simpar$drawn_K[MAX_SPLIT + 1]
  #simpar$drawn_AduZ[MAX_SPLIT + 1]
  #simpar$drawn_JuvZ[MAX_SPLIT + 1]
  simpar$SpawnEnergy    <- rep(0.0, simpar$juv_N + 1)
  simpar$SpawnX         <- rep(0.0, simpar$juv_N + 1)
  simpar$SpawnAllocR    <- rep(0.0, simpar$juv_N + 1)
  simpar$SpawnAllocG    <- rep(0.0, simpar$juv_N + 1)

  simpar$recruits       <- rep(0.0, simpar$juv_N + 1)
  simpar$RzeroS         <- rep(0.0, simpar$juv_N + 1)
  simpar$baseEggsStanza <- rep(0.0, simpar$juv_N + 1)

  simpar$baseSpawnBio   <- rep(0.0, simpar$juv_N + 1)
  simpar$Rbase          <- rep(0.0, simpar$juv_N + 1)
  simpar$RscaleSplit    <- rep(0.0, simpar$juv_N + 1)
    
  simpar$JuvNum         <- c(0, juv$JuvNum)
  simpar$AduNum         <- c(0, juv$AduNum)
  simpar$RecMonth       <- c(0, juv$RecMonth)
  simpar$VonBD          <- c(0, juv$VonBD)
	simpar$aduEqAgeZ      <- c(0, juv$JuvZ_BAB)
	simpar$juvEqAgeZ      <- c(0, juv$AduZ_BAB)
  simpar$RecPower       <- c(0, juv$RecPower)
  simpar$Wmat001        <- c(0, juv$Wmat001)
  simpar$Wmat50         <- c(0, juv$Wmat50)
  simpar$Amat001        <- c(0, juv$Amat001)
  simpar$Amat50         <- c(0, juv$Amat50)
    
  #first calculate the number of months in each age group.  
  #For end stanza (plus group), capped in EwE @400, this is 90% of 
  #relative max wt, uses generalized exponent D
  firstMoJuv <- rep(0, simpar$juv_N) 
  lastMoJuv  <- juv$RecAge * STEPS_PER_YEAR - 1
  firstMoAdu <- juv$RecAge * STEPS_PER_YEAR
  lastMoAdu  <- floor(log(1.0 - (0.9 ^ (1.0 - juv$VonBD))) /
                        (-3.0 * juv$VonBK * (1.0 - juv$VonBD) / STEPS_PER_YEAR))
  lastMoAdu  <- ifelse(lastMoAdu > MAX_MONTHS_STANZA, 
                       MAX_MONTHS_STANZA, 
                       lastMoAdu)

  #Energy required to grow a unit in weight (scaled to Winf = 1)
  vBM <- 1.0 - 3.0 * juv$VonBK / STEPS_PER_YEAR

  #Set Q multiplier to 1 (used to rescale consumption rates) 
  Qmult <- rep(1.0, simpar$NUM_GROUPS) 
 
  #Survival rates for juveniles and adults
  #KYA Switched survival rate out of BAB == assume all on adults
  survRate_juv_month <- exp(-(juv$JuvZ_BAB) / STEPS_PER_YEAR)
  survRate_adu_month <- exp(-(juv$AduZ_BAB) / STEPS_PER_YEAR)

  WmatSpread <- -(juv$Wmat001 - juv$Wmat50) / MIN_REC_FACTOR
  AmatSpread <- -(juv$Amat001 - juv$Amat50) / MIN_REC_FACTOR

  #Save numbers that can be saved at this point
  simpar$WmatSpread  <- c(0, WmatSpread)    
  simpar$AmatSpread  <- c(0, AmatSpread)
  simpar$vBM         <- c(0, vBM)
  simpar$firstMoJuv  <- c(0, firstMoJuv)
  simpar$lastMoJuv   <- c(0, lastMoJuv)
  simpar$firstMoAdu  <- c(0, firstMoAdu)
  simpar$lastMoAdu   <- c(0, lastMoAdu)       
    
	if(simpar$juv_N > 0){                        
    for(i in 1:simpar$juv_N){
	    #R simpar lookup number for juvs and adults is shifted by 1
      rJuvNum <- juv$JuvNum[i] + 1
      rAduNum <- juv$AduNum[i] + 1
                             
      #vector of ages in months from month 0
      ageMo <- 0:lastMoAdu[i]
        
      #Weight and consumption at age
      WageS <- (1.0 - exp(-3 * juv$VonBK[i] * 
                            (1 - juv$VonBD[i]) * 
                            ageMo / STEPS_PER_YEAR)) ^ (1.0 / (1.0 - juv$VonBD[i]))
      WWa <- WageS ^ juv$VonBD[i]
        
      #Numbers per recruit
      surv <- ifelse(ageMo <= firstMoAdu[i], 
                     survRate_juv_month[i] ^ ageMo,
                     survRate_juv_month[i] ^ firstMoAdu[i] * 
                       survRate_adu_month[i] ^ (ageMo - firstMoAdu[i])
                      )
      #plus group
      surv[lastMoAdu[i] + 1] <- surv[lastMoAdu[i]] * survRate_adu_month[i] / 
        (1.0 - survRate_adu_month[i])
            
      #correct if using monthly pulse recruitment
      if(juv$RecMonth[i] > 0){
        lastsurv               <- surv[lastMoAdu[i]] * (survRate_adu_month[i] ^ 12) / 
                                   (1.0 - survRate_adu_month[i] ^ 12)
        surv                   <- (((ageMo + juv$RecMonth[i]) %% 12) == 0) * surv     
        surv[lastMoAdu[i] + 1] <- lastsurv
        }
        
      #Vectors of ages for adults and juvs (added for R)
      AduAges <- (ageMo >= firstMoAdu[i])
      JuvAges <- (ageMo <= lastMoJuv [i])
          
      #Sum up biomass per egg in adult group
      BioPerEgg <- sum(AduAges * surv * WageS)
        
      #Actual Eggs is Biomass of Rpath/Biomass per recruit  
      recruits <- simpar$B_BaseRef[rAduNum] / BioPerEgg
      #KYA Also took BAB out of here (don't know if this is a juv. or adu term)
      #RzeroS[i] <- recruits
      #RzeroS[i] = recruits * exp(juv_aduBAB[i]/ STEPS_PER_YEAR);;  
       
      #Now scale numbers up to total recruits   
      NageS <- surv * recruits 
        
      #calc biomass of juvenile group using adult group input
      #adults should be just a check should be same as input adult bio 
      juvBio <- sum(JuvAges * NageS * WageS)
      aduBio <- sum(AduAges * NageS * WageS)
          
      #calculate adult assimilated consumption   
      sumK <- sum(AduAges * NageS * WWa)

      #SumK is adjusted to QB, ratio between the two is A term in respiration
      #Actually, no, since Winf could scale it up, it could be above or below
      #Q/B
    	sumK  <- simpar$FtimeQBOpt[rAduNum] * simpar$B_BaseRef[rAduNum] / sumK
      aduQB <- simpar$FtimeQBOpt[rAduNum]

      #Calculate initial juvenile assimilated consumption
      juvCons <- sum(JuvAges * NageS * WWa)          

      #Scale Juvenile consumption by same A as adults
      juvCons <- juvCons *  sumK 
      juvQB   <- juvCons / juvBio 

      #Following is from SplitSetPred
      #v->stanzaBasePred[juv_JuvNum[i]] = v->stanzaPred[juv_JuvNum[i]];
      #v->stanzaBasePred[juv_AduNum[i]] = v->stanzaPred[juv_AduNum[i]]; 
      #Moved from the "second" juvenile loop - splitalpha calculation
      JuvBasePred <- sum(JuvAges * NageS * WWa) 
      AduBasePred <- sum(AduAges * NageS * WWa) 
      
      #Consumption for growth between successive age classes
      nb       <- length(WageS)
      Diff     <- WageS[2:nb] - vBM[i] * WageS[1:(nb - 1)]
      Diff[nb] <- Diff[nb - 1]  
      
      #Weighting to splitalpha
      SplitAlpha <- Diff * (JuvAges * JuvBasePred / (juvQB * juvBio) +
                              AduAges * AduBasePred / (aduQB * aduBio))
    
      #Calculate spawning biomass as the amount of biomass over Wmat.
      ##R Comment:  LONGSTANDING Error in C code here? (ageMo > Wmat001[i]))
      SpawnBio <- sum(((WageS > juv$Wmat001[i]) & (ageMo > juv$Amat001[i])) *
                        WageS * NageS /
                        (1 + exp(-((WageS - juv$Wmat50[i]) / WmatSpread[i])   
                                   -((ageMo - juv$Amat50[i]) / AmatSpread[i]))))
		  #cat(i,SpawnBio,"\n")
      #Qmult is for scaling to the PreyTo list so uses actual juvnum, not juvnum + 1					
      Qmult[juv$JuvNum[i]] <- juvCons / (simpar$FtimeQBOpt[rJuvNum] * simpar$B_BaseRef[rJuvNum])

      #R comment:  FOLLOWING CHANGES simpar
      #Set NoIntegrate flag (negative in both cases, different than split pools)
      simpar$NoIntegrate[rJuvNum] <- -juv$JuvNum[i]
      simpar$NoIntegrate[rAduNum] <- -juv$AduNum[i]

      #Reset juvenile B and QB in line with age stucture
      simpar$FtimeAdj  [rJuvNum] <- 0.0
      simpar$FtimeAdj  [rAduNum] <- 0.0
      simpar$FtimeQBOpt[rJuvNum] <- juvQB
      simpar$FtimeQBOpt[rAduNum] <- aduQB 
      simpar$B_BaseRef [rJuvNum] <- juvBio
    
      #KYA Spawn X is Beverton-Holt.  To turn off Beverton-Holt, set
      #SpawnX to 10000 or something similarly hight.  2.0 is half-saturation.
      #1.000001 or so is minimum.
      k <- i + 1
      simpar$SpawnX[k]         <- 10000.0
      simpar$SpawnEnergy[k]    <- 1.0 
      simpar$SpawnAllocR[k]    <- 1.0
      simpar$SpawnAllocG[k]    <- 1.0
      simpar$SpawnBio[k]       <- SpawnBio
      simpar$baseSpawnBio[k]   <- SpawnBio
      simpar$EggsStanza[k]     <- SpawnBio
      simpar$baseEggsStanza[k] <- SpawnBio
      simpar$Rbase[k]          <- NageS[lastMoJuv[i] + 1] * WageS[lastMoJuv[i] + 1]            
      #leaving out code to rescale recruitment if recruitment is seasonal
      #calculates RscaleSplit[i] to give same annual avg as equal monthly rec
      simpar$RscaleSplit[k]     <- 1.0

      simpar$recruits[k]       <- recruits
      simpar$RzeroS[k]         <- recruits
      simpar$stanzaGGJuv[k]    <- juvQB * juvBio / JuvBasePred
      simpar$stanzaGGAdu[k]    <- aduQB * aduBio / AduBasePred

      simpar$state_NN[rJuvNum]       <- sum(NageS * JuvAges)
      simpar$stanzaPred[rJuvNum]     <- JuvBasePred
      simpar$stanzaBasePred[rJuvNum] <- JuvBasePred

      simpar$state_NN[rAduNum]       <- sum(NageS * AduAges)
      simpar$stanzaPred[rAduNum]     <- AduBasePred
      simpar$stanzaBasePred[rAduNum] <- AduBasePred

      simpar$WageS     [1:(lastMoAdu[i] + 1), k] <- WageS
      simpar$WWa       [1:(lastMoAdu[i] + 1), k] <- WWa
      simpar$NageS     [1:(lastMoAdu[i] + 1), k] <- NageS
      simpar$SplitAlpha[1:(lastMoAdu[i] + 1), k] <- SplitAlpha
                     
    }  #END OF JUVENILE LOOP
	}
  #Reset QQ in line with new comsumtion
  #simpar$QQ <- simpar$QQ * Qmult[simpar$PreyTo]

  #Old ecosim_pack-------------------------------------------------------------------- 
  simpar$YEARS  <- YEARS

  
  simpar$BURN_YEARS <- -1
  simpar$COUPLED    <-  1
 
  simpar$CRASH_YEAR <- -1
  
  #derivlist
  simpar$TotGain        <- rep(0.0, simpar$NUM_GROUPS + 1)
  simpar$TotLoss        <- rep(0.0, simpar$NUM_GROUPS + 1)
  simpar$LossPropToB    <- rep(0.0, simpar$NUM_GROUPS + 1)
  simpar$LossPropToQ    <- rep(0.0, simpar$NUM_GROUPS + 1)
  simpar$DerivT         <- rep(0.0, simpar$NUM_GROUPS + 1)
  simpar$dyt            <- rep(0.0, simpar$NUM_GROUPS + 1)
  simpar$biomeq         <- rep(0.0, simpar$NUM_GROUPS + 1)
  simpar$FoodGain       <- rep(0.0, simpar$NUM_GROUPS + 1)
  simpar$DetritalGain   <- rep(0.0, simpar$NUM_GROUPS + 1)
  simpar$FoodLoss       <- rep(0.0, simpar$NUM_GROUPS + 1)
  simpar$UnAssimLoss    <- rep(0.0, simpar$NUM_GROUPS + 1)
  simpar$ActiveRespLoss <- rep(0.0, simpar$NUM_GROUPS + 1)
  simpar$MzeroLoss      <- rep(0.0, simpar$NUM_GROUPS + 1)
  simpar$DetritalLoss   <- rep(0.0, simpar$NUM_GROUPS + 1)
  simpar$TotDetOut      <- rep(0.0, simpar$NUM_GROUPS + 1)
  simpar$FishingLoss    <- rep(0.0, simpar$NUM_GROUPS + 1)
  simpar$FishingGain    <- rep(0.0, simpar$NUM_GROUPS + 1)
  simpar$FishingThru    <- rep(0.0, simpar$NUM_GROUPS + 1)
  simpar$preyYY         <- rep(0.0, simpar$NUM_GROUPS + 1)
  simpar$predYY         <- rep(0.0, simpar$NUM_GROUPS + 1)
  simpar$PredSuite      <- rep(0.0, simpar$NUM_GROUPS + 1)
  simpar$HandleSuite    <- rep(0.0, simpar$NUM_GROUPS + 1)
  simpar$TerminalF      <- rep(0.0, simpar$NUM_GROUPS + 1)
 
  
  #targlist     
  simpar$TARGET_BIO <- rep(0.0, simpar$NUM_GROUPS + 1)
  simpar$TARGET_F   <- rep(0.0, simpar$NUM_GROUPS + 1)
  simpar$ALPHA      <- rep(0.0, simpar$NUM_GROUPS + 1)
  
  mforcemat           <- data.frame(matrix(1.0, YEARS * 12 + 1, simpar$NUM_GROUPS + 1))
  names(mforcemat)    <- simpar$spname
  simpar$force_byprey   <- mforcemat
  simpar$force_bymort   <- mforcemat
  simpar$force_byrecs   <- mforcemat
  simpar$force_bysearch <- mforcemat
  
  yforcemat         <- data.frame(matrix(0.0, YEARS + 1, simpar$NUM_GROUPS + 1))
  names(yforcemat)  <- simpar$spname
  simpar$FORCED_FRATE <- yforcemat
  simpar$FORCED_CATCH <- yforcemat

  omat           <- data.frame(matrix(0.0, YEARS * 12 + 1, simpar$NUM_GROUPS + 1))
  names(omat)    <- simpar$spname
  simpar$out_BB  <- omat 
  simpar$out_CC  <- omat
  simpar$out_SSB <- omat              
  simpar$out_rec <- omat
  
  class(simpar) <- 'Rpath.sim'
  return(simpar)

}
 

##------------------------------------------------------------------------------ 

ecosim_run <- function(simpar, BYY = 0, EYY = 0){
  if((EYY <= 0) | (EYY > simpar$YEARS)) EYY <- simpar$YEARS
  if(BYY <0)                          BYY <- 0
  if(BYY >= simpar$YEARS)               BYY <- simpar$YEARS - 1
  if(EYY <= BYY)                      EYY <- BYY + 1

  out <- simpar
  res<-.C("ecosim_run", 
    # inputs that shouldn't change
    as.integer(simpar$YEARS),
    as.integer(BYY),
    as.integer(EYY),
    as.integer(simpar$numlist),
    as.integer(simpar$flags),
    as.double(as.matrix(simpar$ratelist)),
    as.integer(as.matrix(simpar$ppind)),
    as.double(as.matrix(simpar$pplist)),
    as.integer(as.matrix(simpar$fishind)),
    as.double(as.matrix(simpar$fishlist)),
    as.integer(as.matrix(simpar$detind)),
    as.double(as.matrix(simpar$detlist)),
    as.integer(as.matrix(simpar$juvind)),
    as.double(as.matrix(simpar$juvlist)),
    as.double(as.matrix(simpar$targlist)),
    # outputs that should
    outflags       = as.integer(simpar$outflags),  
    state          = as.double(as.matrix(simpar$statelist)),
    NageS          = as.double(simpar$NageS),
    WageS          = as.double(simpar$WageS),
    WWa            = as.double(simpar$WWa),
    SplitAlpha     = as.double(simpar$SplitAlpha),
    derivlist      = as.double(as.matrix(simpar$derivlist)),
    force_byprey   = as.double(as.matrix(simpar$force_byprey)),
    force_bymort   = as.double(as.matrix(simpar$force_bymort)),
    force_byrecs   = as.double(as.matrix(simpar$force_byrecs)),
    force_bysearch = as.double(as.matrix(simpar$force_bysearch)),
    FORCED_FRATE   = as.double(as.matrix(simpar$FORCED_FRATE)),
    FORCED_CATCH   = as.double(as.matrix(simpar$FORCED_CATCH)),
    out_BB         = as.double(as.matrix(simpar$out_BB)),
    out_CC         = as.double(as.matrix(simpar$out_CC)),
    out_SSB        = as.double(as.matrix(simpar$out_SSB)), 
    out_rec        = as.double(as.matrix(simpar$out_rec)))
  
  out$outflags[]   <- res$outflags
  out$derivlist[]  <- res$derivlist
  out$statelist[]  <- res$state
  out$NageS[]      <- res$NageS
  out$WageS[]      <- res$WageS
  out$WWa[]        <- res$WWa
  out$SplitAlpha[] <- res$SplitAlpha
  out$out_BB[]     <- res$out_BB
  out$out_CC[]     <- res$out_CC
  out$out_SSB[]    <- res$out_SSB  
  out$out_rec[]    <- res$out_rec

  return(out)
}

