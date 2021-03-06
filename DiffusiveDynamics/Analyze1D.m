(* Mathematica Package *)

(* Created by the Wolfram Workbench 14.1.2013 *)

BeginPackage["DiffusiveDynamics`Analyze1D`",{"DiffusiveDynamics`Utils`","CCompilerDriver`"(*,"DiffusiveDynamics`Visualize1D`"*)}]
(* Exported symbols added here with SymbolName::usage *) 

(*Fallback gracefully if no C compiler is present*)
If[Length@CCompilers[]>0,
    $Analyze1DCompilationTarget="C"
,(*else*)    
    $Analyze1DCompilationTarget="WVM"];

ClearAll[GetDiffusionInBin1D];
GetDiffusionInBin1D::usage="GetDiffusionInBin1D
Diffusion info contains:
x,   -- the positiopn of the bin 
ux  -- the mean of the distribution
Dx  -- the diffusion 
Stride -- how many steps are steps are joined into one step.
xWidth -- the width of the bin
StepsInBin     -- how many steps in are in this bin
StepsHistogram -- draw the histogram of steps
PValue,IsNormal-- The PValue and the outcome of the normality test.
" 


ClearAll[GetDiffusionInBins1D]
GetDiffusionInBins1D::usage="TODO"

ClearAll[compiledSelectBin1D];
compiledSelectBin1D::usage="compiledSelectBin1D[points, min, max] 
Takes a list of 2D points and the boundaries of the bin (min, max). 
Returns all the points that are in the bin (between min and max)";

ClearAll[compiledGetContigIntervals1D]
compiledGetContigIntervals1D::usage="Returns the intervals where the difference between the sorted integers is not 1

Params:
   ind -- a floating point list of integers eg {1., 2., 3. ,6. 7. 8.}

Result:
   a list of intervals as a packed (integer) array. For example:
   {{1, 3}, {6,8}}";

ClearAll[CompileFunctions1D,CompileFunctionsIfNecessary1D];
CompileFunctions1D::usage="CompileFunctions1D[] recompiles all CompiledFunctions in package. Use $Analyze1DCompilationTarget to set the compilation target to \"C\" or \"VWM\"";
CompileFunctionsIfNecessary1D::usage="CompileFunctionsIfNecessary1D[] only compiles functions if they have not been compiled yet";

ClearAll[GetDiffusionInBinsBySelect1D];
GetDiffusionInBinsBySelect1D::usage="TODO";

ClearAll[GetDiffusionInfoFromParameters1D, GetDiffusionInfoFromParametersWithStride1D];
GetDiffusionInfoFromParameters1D::usage="GetDiffusionInfoFromParameters1D[binsOrBinspec, stride|strides,DiffX] 
Returns a list of rules about diffusion from the DiffX functions."



ClearAll[LoadDiffusions1D, SaveDiffusions1D];
LoadDiffusions1D::usage="LoadDiffusions1D[name, opts]
Loads the diffusions from the directory name. Returns a list of:

  {\"Metadata\" -> metadata,
   \"Diffusions\" -> diffs,
   \"RawSteps\" -> rawSteps}
";


SaveDiffusions1D::usage="SaveDiffusions1D[name, diffs, opts]. \n Saves the diffusions diffs to a directory specified by name. Metadata can be given as na option.";

ClearAll[EstimateDiffusionError1D];
EstimateDiffusionError1D::usage="";

GetDiffusionsRMSD1D::usage="";

Begin["`Private`"]
(* Implementation of the package *)
$SignificanceLevel = 0.05;
 
(*SetAttributes[GetDiffusionInBin1D,HoldFirst];*)



Options[GetDiffusionInBin1D] := {"Verbose":>$VerbosePrint,  (*Log output*)
						   "VerboseLevel":>$VerboseLevel,(*The amount of details to log. Higher number means more details*)
                           "Strides"->1.,     (*How many points between what is considered to be a step- 1 means consecutive points in the raw list*)
                           "PadSteps"->True,     (*Take points that are outside of the bin on order to improve the statistics *)
                           "ReturnRules"->True,  (*Return the results as a list of rules*)
                           "ReturnStepsHistogram"->False, (*Returns the density histogram of steps. Slows down the calcualtion considerably. Useful for debuging and visualization.*)
                           "WarnIfEmpty"->False, (*Prints a warning if too litle points in bin*)
                           "NormalitySignificanceLevel"-> .05 (*Significance level for the normality test*)
           }~Join~Options[GetDiffsFromBinnedPoints];
 
GetDiffusionInBin1D[rwData_,dt_,{min_,max_},{cellMin_,cellMax_},opts:OptionsPattern[]] :=
Block[{$VerbosePrint=OptionValue["Verbose"], $VerboseLevel=OptionValue["VerboseLevel"],$VerboseIndentLevel=$VerboseIndentLevel+1,
       $SignificanceLevel=OptionValue@"NormalitySignificanceLevel"}, 
    Module[ {data,t,diffs,bincenter,binwidth,sd},
            Puts["***GetDiffusionInBin1D****"];
			Assert[Last@Dimensions@rwData==2,"Must be a list of tuplets in the form {t,x}"];
			Assert[Length@Dimensions@rwData==3,"rwData must be a list of lists of tuplets!"];
            Puts[Row@{"\ndt: ",dt,"\nmin: ",min,"\nmax: ",max,"\ncellMin: ",cellMin,"\ncellMax: ",cellMax},LogLevel->2];
            PutsOptions[GetDiffusionInBin1D, {opts}, LogLevel->2];
			CompileFunctionsIfNecessary1D[];
            PutsE["original data:\n",rwData,LogLevel->5];
            Puts["Is packed original data? ",And@@Developer`PackedArrayQ[#]&/@rwData, LogLevel->5];

            bincenter = (max+min)/2.;
            binwidth = (max-min);
            
            (*if OptionValue["Strides"] only one number and not a list convert it to list {x}*)
            sd = If[ NumericQ[OptionValue["Strides"]],
                     {OptionValue["Strides"]},
                     OptionValue["Strides"]
                 ];            
       
            If[OptionValue@"WarnIfEmpty",On[GetStepsFromBinnedPoints::zerodata],
                                         Off[GetStepsFromBinnedPoints::zerodata]];
                        
            (*select the steps in the bin*)
            (*Take just the step's indexes*)
            t = AbsoluteTiming[   
                   data = Map[Part[compiledSelectBin1D[#,min,max],All,1]&,rwData];
             ];
      
            Puts["select data took: ", First@t,LogLevel->2];

            
            t = AbsoluteTiming[   
                   data = Map[(If[Length[#] != 0, 
                                   Interval@@compiledGetContigIntervals1D[#], (*UNPACKING here*)
                                   Interval[]]
                               )&,data];
             ];
            
            Puts["Finding contigous inds took: ", First@t, LogLevel->2];
            PutsE["after select and contig:\n",data, LogLevel->5];

            

            diffs = Map[With[{stepdelta = #},
                            GetDiffsFromBinnedPoints[data,rwData,dt,{min,max},{cellMin,cellMax}
                            ,"Stride"->stepdelta
                            ,"PadSteps"->OptionValue["PadSteps"],"PadOnlyShort"->OptionValue@"PadOnlyShort"
                            ,"ReturnStepsHistogram"->OptionValue["ReturnStepsHistogram"]]
                        ]&,sd];
            diffs
        ]
]; 

ClearAll[compiledSelectBinFunc1D];
compiledSelectBinFunc1D = Compile[{{point,_Real, 1},{min,_Real, 0},{max,_Real,0}},
  (point[[2]]>=min )&&(point[[2]]<=max)
,  
   CompilationOptions->{"ExpressionOptimization"->True,"InlineExternalDefinitions"->True},
   "RuntimeOptions"->"Speed"];
  
(*The delayed definition := is just a trick to compile functions on first use. makes packages load quicker*)	
ClearAll[compiledSelectBinUncompiled];
compiledSelectBinUncompiled[]:= Block[{points,min,max},   (*This block is just for syntax coloring in WB*) 
compiledSelectBin1D = Compile[{{points,_Real, 2},{min,_Real, 0},{max,_Real, 0}},
  Select[points,compiledSelectBinFunc1D[#,min,max]&]
,  CompilationTarget->$Analyze1DCompilationTarget,
   CompilationOptions->{"ExpressionOptimization"->True,"InlineCompiledFunctions"->True,"InlineExternalDefinitions"->True},
   "RuntimeOptions"->"Speed"];
] 

(*Returns the intervals where the difference between the sorted integers is not 1

Params:
   ind -- a floating point list of integers eg {1., 2., 3. ,6. 7. 8.}

Result:
   a list of intervals as a packed (integer) array. For example:
   {{1, 3}, {6,8}}
*)

ClearAll[compiledGetContigIntervals1D, compiledGetContigIntervalsUncompiled];
compiledGetContigIntervalsUncompiled[]:=Block[{ind},   (*This block is just for syntax coloring in WB*) 
	compiledGetContigIntervals1D = Compile[{{ind,_Real, 1}},
	    Block[{i, openInterval = 0, result = Internal`Bag[Most@{0}]},
	        
	        openInterval = Round@ind[[1]];(*the first oppening interval*)
	        
	        (*loop through all the indices and check for diffrences <> 1. If that is the case stuff the interval *)
	        (*Floating points implicitly compared with tolerances*)
	        Do[With[{curr=Round@ind[[i]], prev=Round@ind[[i-1]]},
	            If[ (curr-prev)!=1,
	             Internal`StuffBag[result, openInterval];
	             Internal`StuffBag[result, prev ];
	             openInterval=curr;      
	             ];
	        ], {i,2,Length@ind}];

           Internal`StuffBag[result, openInterval];    
           Internal`StuffBag[result, Round@ind[[-1]]];
	       (*return the intervals*) 
	       Partition[Internal`BagPart[result, All], 2]
	    ]  
	,CompilationTarget->$Analyze1DCompilationTarget, 
   CompilationOptions->{"ExpressionOptimization"->True,"InlineExternalDefinitions"->True},
   "RuntimeOptions"->{"Speed","CompareWithTolerance"->False}];
];
ClearAll[GetDiffsFromBinnedPoints];
Attributes[GetDiffsFromBinnedPoints]={HoldAll};
(*SetAttributes[GetDiffsFromBinnedPoints,{HoldAll}];*)
Options[GetDiffsFromBinnedPoints] := {"Verbose":>$VerbosePrint,  (*Log output*)
						        "VerboseLevel":>$VerboseLevel,(*The amount of details to log. Higher number means more details*)
                                "Stride"->1., (*kdaj sta dva koraka zaporedna*)
                                "ReturnStepsHistogram"->True}~Join~Options[GetStepsFromBinnedPoints];
GetDiffsFromBinnedPoints[binnedIndInterval_,rwData_,dt_,{min_,max_},{cellMin_,cellMax_},opts:OptionsPattern[]] :=
    Block[ {$VerbosePrint = OptionValue["Verbose"], $VerboseLevel = OptionValue["VerboseLevel"],$VerboseIndentLevel = $VerboseIndentLevel+1},
        Module[ {steps, bincenter = (min+max)/2,binwidth = (max-min)},
            Puts["***GetDiffsFromBinnedPoints***"];
            PutsOptions[GetDiffsFromBinnedPoints,{opts},LogLevel->2];
            
            steps = Developer`ToPackedArray@Flatten[
                    Table[GetStepsFromBinnedPoints[binnedIndInterval[[i]],rwData[[i]],dt,{min,max},{cellMin,cellMax} 
                            ,"Stride"->OptionValue["Stride"], "Verbose"->OptionValue["Verbose"]
                            ,"PadSteps"->OptionValue["PadSteps"],"PadOnlyShort"->OptionValue@"PadOnlyShort"]
                          ,{i,Length[rwData]}]
                  ,1];

            PutsE["Steps:\n",steps,LogLevel->5];

            GetDiffsFromSteps[steps,dt, OptionValue["Stride"]]~Join~{"Stride"->OptionValue["Stride"], "x"->bincenter, 
                      "xWidth"->binwidth,  "StepsInBin"->Length[steps], "dt"->dt,
                      "StepsHistogram"->If[ OptionValue["ReturnStepsHistogram"],
                                            N@HistogramList[steps,"Sturges","PDF"]
                                        ]}
        ]
    ];


ClearAll[GetStepsFromBinnedPoints];
Attributes[GetStepsFromBinnedPoints]={HoldAll};

Options[GetStepsFromBinnedPoints] = {"Verbose":>$VerbosePrint,  (*Log output*)
						        "VerboseLevel":>$VerboseLevel,  (*The amount of details to log. Higher number means more details*)
                                "Stride"->1.,                   (*Number of points between a step*)
                                "PadSteps"->True,               (*if Stride steps should be added to each continous segment of the trayectory in bbin*)
                                "PadOnlyShort"->True            (*Pad only intervals smaller or equal than ds (If PadSteps is true) *)};

GetStepsFromBinnedPoints::zerodata =            "Zero data (empty list) in bin {`1`,`2`}! Returning empty list";
GetStepsFromBinnedPoints[binnedIndInterval_,rwData_,dt_,{min_,max_},{cellMin_,cellMax_},opts:OptionsPattern[]] :=
Block[ {$VerbosePrint = OptionValue["Verbose"], $VerboseLevel = OptionValue["VerboseLevel"],$VerboseIndentLevel = $VerboseIndentLevel+1},
    Module[ {data,indpaths,cellWidth,bincenter,ds,indLengths},
            Puts["********GetStepsFromBinnedPoints********",LogLevel->1];
            PutsOptions[GetStepsFromBinnedPoints,{opts},LogLevel->2];
            Puts[Row@{"min: ", min," max: ", max},LogLevel->2];
            Puts[Row@{"cellMin: ", cellMin," cellMax: ", cellMax},LogLevel->2];
            PutsE["rwData:\n",rwData,LogLevel->5];
            PutsE["binnedInd:\n",binnedIndInterval,LogLevel->3];
            Puts["Length rwData: ",Length[rwData],LogLevel->2];
            If[ Length@binnedIndInterval>0, (*then*)
                Puts["binnedInd min: ",Min@binnedIndInterval," max: ", Max@binnedIndInterval,LogLevel->2];
            ];

            ds = OptionValue["Stride"];
            If[ Length[binnedIndInterval]==0,(*then*)
                Message[GetStepsFromBinnedPoints::zerodata,min,max];
                Return[{}];
            ];
            cellWidth = (cellMax-cellMin);
            bincenter = (min+max)/2;


            indpaths = binnedIndInterval;
            PutsE["Indpaths: ", indpaths,LogLevel->5];
            PutsE["Indpaths lengths:\n",indLengths=(Last@#-First@#+1)&/@(List@@indpaths),LogLevel->3];
            PutsF["Indpaths count `` mean ``:\n",Length@indLengths, N@Mean@indLengths, LogLevel->3];
            Puts[Histogram[indLengths,{5},PlotRange->{{0,All},{0,All}}],LogLevel->6];
            (*Add ds steps to the begining and end, so that we get at least 2 steps for each point in bin at largest ds*)
            (*Do this only if length of path is less or equal to  ds *)
            If[ OptionValue["PadSteps"], (*then*)
                (*Expand the intervals. Unions are automagically preformed*)
                
                If[ OptionValue@"PadOnlyShort", (*Hmm, mogo�e bi lahko tukaj paddal samo toliko, da bi bila dol�ina 2ds namesto last+2ds*)
                    indpaths=If[(Last@# - First@#) <= ds, {First@# - ds, Last@# + ds}, #] & /@indpaths;
                     Puts["PaddingOnlyShort",LogLevel->5];
                ,(*else*)
                    indpaths = indpaths + Interval[{-ds, ds}];
                    Puts["PaddingAll",LogLevel->5];
                ]; 

                (*Stay within the limits*)
                indpaths = IntervalIntersection[indpaths, Interval[{1, Length@rwData}]];
                 
                PutsF["After padding (with `1`):",ds,LogLevel->2]; 
                PutsE["Indpaths: ", indpaths,LogLevel->5];
                PutsE["Indpaths lengths:\n",indLengths=(Last@#-First@#+1)&/@(List@@indpaths),LogLevel->3];
                PutsF["Indpaths count `` mean `` (after padding ``):\n",Length@indLengths, N@Mean@indLengths,ds, LogLevel->3];
                Puts[Histogram[indLengths,{5},PlotRange->{{0,All},{0,All}}],LogLevel->6];
                (*Puts["Mean (after padding): ",N@Mean[(Differences[#]+1)&/@indpaths],LogLevel->0];
                Puts[Histogram[(Differences[#]+1)&/@indpaths,{5},PlotRange->{{0,All},{0,All}}],LogLevel->3];*)
                
            ];
            
            Puts["Before getting data",LogLevel->5];
            (*get the contigs x*)
            (*Padding somoetimes gives non integer intervals? From where?*)
            data = rwData[[Round@First@#;;Round@Last@#,2]]&/@(List@@indpaths);(*UNPACKING here? *)
            Puts["After getting data",LogLevel->5];
            PutsE["All data:\n",data,LogLevel->5];
            Puts["After getting data is it packed? ",Developer`PackedArrayQ@data,LogLevel->5];
            Puts["data is packed: ", And@@(Developer`PackedArrayQ[#]&/@data),LogLevel->2];
            Puts[
             Module[ {dp},
                 dp = StrideData[Flatten[data,1],5000];
                 (*dp=Tooltip[#[[{2,3}]],#[[1]]]&/@dp;*)
                 
                 ListPlot[dp,Frame->True,Axes->False,PlotStyle->Opacity[.4],PlotRange->{All,{cellMin,cellMax}}
                        ,FrameLabel->{"timestep","X coordinate"}
                        ,GridLines->{{},{min,max}}
                        ,GridLinesStyle->Directive[Thick]
                        ,ImageSize->Medium]
             ],LogLevel->3];


            
           (*calculate the steps (diferences between consecutive points*)
            Puts["Before getting Diffrences",LogLevel->5];
           
                       
            data = (If[Length[#]<=ds,{},(*If less than ds steps, then return empty list*)
                    Drop[#,ds]-Drop[#,-ds]])&/@data; (*UNPACKING here? *)
            
            (*This is not supported in mma 8.
            BUG IN Differences??
            If[$VersionNumber>=9,
                data = Differences[#,1,ds]&/@data;
            ,(*else*)
                data = (Drop[#,ds]-Drop[#,-ds])&/@data;
            ];*)
            Puts["After getting Diffrences",LogLevel->5];

            (*Delete empty lists (*TODO: Perhaps this is still needed?*)
            data = DeleteCases[data,{{}}];*)
            

            
            data = Developer`ToPackedArray[Flatten[data,1]]; (*UNPACKING here! *)

            If[ Length[data]===0,(*then*)
                Message[GetStepsFromBinnedPoints::zerodata,min,max];
                Return[{}];
            ];

            (*Pick the shortest of the steps. This is needed if the step was over the periodic boundary limit. 
            Used for each ccordinate seperatly.
            MakeInPeriodicCell is listable.*)
            Puts["Before Calling MakeInPeriodicCell",LogLevel->4];
            data= MakeInPeriodicCell[data, cellWidth];
            Puts["After Calling MakeInPeriodicCell",LogLevel->4];	            
            
            
            

            
            PutsE["Steps: \n",data,LogLevel->5];
            
            Puts["Steps are packed: ", Developer`PackedArrayQ[data], LogLevel->2];
            PutsF["STEPS: num ``; average length `` ",Length[data],Mean[Norm/@data],LogLevel->2];
               



            
            (*Puts[Module[{g,plr},
              g=DensityHistogram[data,30(*,PerformanceGoal->"Speed"*)];
              plr={Min@#1,Max@#2}&@@Transpose[PlotRange/.Options[g]];
              Show[g,PlotRange->{plr,plr}]

            ]];*)
            (*alternativno iz drugih momentov*)
            Return[data];
        ]
    ];
(************************************************************************)
ClearAll[GetDifferences,GetDifferencesUncompiled];
GetDifferencesUncompiled[] := Block[{l,ds}, 
GetDifferences = Compile[{{l,_Real, 2},{ds,_Integer,0}},
  Block[ {lr},
      lr = {{}};
      (*If[ds==1,(*then*)lr=Differences[l];];*)
      If[ Length[l]>ds,(*if list is long enough then*)
          lr = Drop[l,ds]-Drop[l,-ds]
      ];
      lr
  ],
 CompilationTarget->$Analyze1DCompilationTarget, 
   CompilationOptions->{"ExpressionOptimization"->True,"InlineExternalDefinitions"->True},
   "RuntimeOptions"->{"Speed","CompareWithTolerance"->True}];
];


ClearAll[GetDiffsFromSteps];
(*Takes a list of steps {{dx,dy}, ...} and calculates the diffusion constants.
data -- list of steps
dt   -- the timestep in units of time
ds   -- the stride of timeteps (how many steps are skipped. Unitless. 

Returns a list of replacement rules for higher flexibility. 
*)
(*TODO: here it would be possible to get parameters using FindDistribution and MultinormalDistribution. 
Or add a test for normality in any other way*) 
Attributes[GetDiffsFromSteps]={HoldFirst};
GetDiffsFromSteps[data_,dt_,ds_] :=  Block[{$VerboseIndentLevel = $VerboseIndentLevel+1},
    Module[ {ux,sx,rDx,pVal,isNormal,
             xMinWidth,allMissing,result},
        allMissing={"Dx"->Missing[],"ux"->Missing[],"sx"->Missing[],
                    "PValue"->Null,"IsNormal"->Null (*Must be null here, otherwise it breaks a Pick later on*),
                    "xMinWidth"->Missing[]};
        Puts["***GetDiffsFromSteps***"];
        If[ Length[data]>10, (*If enough steps then*)
            (*TODO: Perhaps add option to choose if we want the normality test and which test is wanted *)
            (*{ux,uy,rDx,rDy,rDa} = GetTensorFromMoments[data];*)
            {ux,sx,pVal,isNormal}=GetTensorFromMomentsWithNormalityTest[data];
            If[Not[NumericQ@ux && NumericQ@sx], 
                Print["Some of the returned values are not numeric: ",{ux,sx}]; 
                result=allMissing;
                ];
             
            (*We fitted the principal sigmas... transform into diffusion and devide by StepsDelta*)
            rDx = sx^2/(2*dt*ds);
            (*99.7 steps are inside the bin. 3*sigma to each side*)
            xMinWidth=Abs[6*sx];
            
            
            result= {"Dx"->rDx,"ux"->ux,"sx"->sx,
                     "PValue"->pVal,"IsNormal"->isNormal,"xMinWidth"->xMinWidth};
        ,(*else*)
        result=allMissing;        
        ];
        result

    ]
];


(*Takes a list of steps {dx, ...} and calculates the  second moment (standard deviation)
The central second moment is the Sum[(x-ux)^2]/N

Returns {ux,sx,alpha, pVal,isNormal}
mx -- first moment
sx -- standard deviation Sqtr[Sum[(x-ux)^2]/N] 
pVal -- PValue from AndersonDarlingTest
isNormal -- Is this a normal distribution according to AndersonDarlingTest
*)

Options[GetTensorFromMomentsWithNormalityTest]={HoldFirst};
GetTensorFromMomentsWithNormalityTest[data_] :=
    Module[ {ux,sx,dist,hypothesis,params,pVal, isNormal},
		
		dist = NormalDistribution[ux, sx];

		hypothesis=AndersonDarlingTest[data, dist, "HypothesisTestData",SignificanceLevel->$SignificanceLevel]; 
		(*Is normal distribution?*)
		pVal=hypothesis["PValue"];
		isNormal=hypothesis["ShortTestConclusion"] == "Do not reject";
		(*Retrive the parameters*)
		params=hypothesis["FittedDistributionParameters"];
		If[params===Indeterminate, 
		    Print["Could not fit distribution parameters",data];
		    Return@ConstantArray[Missing[],7];
		  ];
		{ux,sx}={ux,sx}/.params;
        Return[{ux,sx,pVal,isNormal}]
    ];


ClearAll[MinAbs];
MinAbs[L_] :=
    First@Sort[L,Abs[#1]<Abs[#2]&];

ClearAll[MakeInPeriodicCell,MakeInPeriodicCellUncompiled];
MakeInPeriodicCellUncompiled[]:=Block[{x,cellwidth},  (*This block is just for syntax coloring in WB*)
(*
Steps through the whole cell are very improbable, so large steps are due to periodic conditions.
Takes a coordinate and chooses the smallest of the three options due to periodic conditions.
*)
MakeInPeriodicCell = Compile[{{x,_Real},{cellwidth,_Real}},
  If[ x<-(cellwidth/2.),(*then*)
      x+cellwidth,
   (*else*)
      If[ x>cellwidth/2., (*then*)
          x-cellwidth,
        (*else*)
          x
      ]
  ]
,CompilationOptions->{"ExpressionOptimization"->True,"InlineCompiledFunctions"->True,"InlineExternalDefinitions"->True},
 RuntimeAttributes->{Listable},
 CompilationTarget->$Analyze1DCompilationTarget,
 "RuntimeOptions"->"Speed"];
];

(*
ClearAll[AppendLeftRight,AppendLeftRightUncompiled];
AppendLeftRightUncompiled[] := Block[{l,ds,max}, (*This block is just for syntax coloring in WB*)
(*Takes a list of indexes and tries to append ds consecutive numbers to the beginning and end 

l   --  list of array indexes in rwData. (sorted) 
ds  --  stride step
max --  length of rwData
TODO: If ds steps can't be added perhaps some smaller number can?*)
AppendLeftRight = Compile[{{l,_Real, 1},{ds,_Real,0},{max,_Real,0}},
  Block[ {lr}, 
      lr = l; (*Have to make a copy that can be modified*)
      If[ (First[lr]-ds)>0, (*if there are some points at the begining then*)
          lr = Range[First[lr]-ds,First[lr]-1]~Join~lr (*add the indexes*)
      ];
      If[ (Last[lr]+ds)<max, (*then*)
          lr = lr~Join~Range[Last[lr]+1,Last[lr]+ds]
      ];
      Return[lr]
  ],
 CompilationTarget->$Analyze1DCompilationTarget,
   CompilationOptions->{"ExpressionOptimization"->True,"InlineExternalDefinitions"->True},
   "RuntimeOptions"->{"Speed","CompareWithTolerance"->True}];
];  *)
 
   
$HaveFunctionsBeenCompiled=False;
(*recompiles teh functions by calling the set delayed definitions*)
CompileFunctions1D[] :=
    (Puts["Compiling functions in Anayze1D.m to ", $Analyze1DCompilationTarget,LogLevel->2];
     AppendLeftRightUncompiled[];
     compiledSelectBinUncompiled[];
     GetDifferencesUncompiled[];
     MakeInPeriodicCellUncompiled[];
     compiledGetContigIntervalsUncompiled[];
     $HaveFunctionsBeenCompiled = True; 
    );

CompileFunctionsIfNecessary1D[]:= If[! $HaveFunctionsBeenCompiled, CompileFunctions1D[]];

(*Gets the bin centers and widths from binspec {min,max,width}*)

GetBinCentersAndWidths1D[binSpec_] :=
    Block[ {$VerboseIndentLevel = $VerboseIndentLevel+1},
        Module[ {bincenters,binwidth},
            Puts["********GetBinCentersAndWidths1D********"];
            bincenters=MovingAverage[Range@@binSpec,2];
            binwidth = binSpec[[3]];
            {#,binwidth}&/@bincenters            
        ]
    ];
     

GetBinsFromBinsOrSpec1D[binsOrBinSpec_]:=
    Module[{isBinSpec, isBinList},
        Puts["********GetBinsFromBinsOrSpec1D********",LogLevel->2];
        isBinSpec=(ArrayDepth@binsOrBinSpec==1); (*this is a bin spec*)
        isBinList=(ArrayDepth@binsOrBinSpec>1); (*this are bins*)
        Assert[isBinSpec || isBinList,"binsOrBinSpec is in wrong format! "<>ToString@Shallow@binsOrBinSpec];
                        
        If[isBinSpec, (*then*)GetBinCentersAndWidths1D@binsOrBinSpec, (*else*)binsOrBinSpec]
    ]    
   
(*takes a list of bins {{x,dx},...} and returns cellRange {minX,minY}*)
(*Todo can be compiled if necessary*)
GetCellRangeFromBins1D[bins_]:= 
    Block[{minPoints, maxPoints,minX,maxX},
        minPoints = (#[[1]] - #[[2]]/2) & /@ bins;
        maxPoints = (#[[1]] + #[[2]]/2) & /@ bins;
        minX=Min[minPoints];
        maxX=Max[maxPoints];
        {minX,maxX}
    ];   
   
(*GetDiffusionInBinsBySelect1D*)
(*Calculates the diffusion coeficients in all bins of the cell. Bining is re-done for each bin by select.  
 rwData --  Data of the diffusion process. A list of points {{t,x,y},...}
 dt     --  the timstep between two points in the units of time 
 binSpec -- specfication of the bins {min,max,dstep}
 cellMinMax The periodic cell limits {{minx,minY},{maxX, maxY}. If Null then taken form binSpec}*)

Options[GetDiffusionInBinsBySelect1D] := {"Parallel"->True,(*Use parallel functions*)
    								   "CellRange"->Automatic (*cell range in {{MinX,MinY},{MaxX,MaxY}}. If automatic, then calculated from binsOrBinSpec*)
							          }~Join~Options[GetDiffusionInBin1D];
Attributes[GetDiffusionInBinsBySelect1D]={HoldFirst};
GetDiffusionInBinsBySelect1D[rwData_,dt_,binsOrBinSpec_,opts:OptionsPattern[]] :=
    Block[ {$VerbosePrint = OptionValue["Verbose"], $VerboseLevel = OptionValue["VerboseLevel"],$VerboseIndentLevel = $VerboseIndentLevel+1},
        Module[ {bins, cellMin,cellMax},
            Puts["********GetDiffusionInBinsBySelect1D********"];
            PutsE["rwData: ",rwData, LogLevel->2];
            PutsE["binsOrBinSpec: ",binsOrBinSpec, LogLevel->2];
            Puts[$VerboseIndentString,"dimensions: ",Dimensions@binsOrBinSpec];
            PutsOptions[GetDiffusionInBinsBySelect1D, {opts}, LogLevel->2];
             
			bins=GetBinsFromBinsOrSpec1D@binsOrBinSpec;
            (*get cellMin/max from the bins if the option for cellRange is automatic*)
            {cellMin,cellMax}=If[#===Automatic,GetCellRangeFromBins1D@bins,#]&@OptionValue@"CellRange";
            PutsE["used cellRange: ",{cellMin,cellMax}, LogLevel->2];
            
            
			If[ OptionValue@"Parallel", (*then*)
            	(*I think distribute definitions also works. Actually it's more approapriate, but I'm not sure if it makes a copy or not...*)
                DistributeDefinitions@rwData;
                With[ {IcellRange = {cellMin,cellMax},Idt = dt,injectedOptions = FilterRules[{opts},Options@GetDiffusionInBin1D]},
                    PutsE["injectedOptions:\n",injectedOptions, LogLevel->1];
                    ParallelMap[
                        GetDiffusionInBin1D[rwData, Idt, {#[[1]]-#[[2]]/2,#[[1]]+#[[2]]/2},IcellRange,injectedOptions]&
                        ,bins]
                ],(*else*)
                With[ {injectedOptions = FilterRules[{opts},Options@GetDiffusionInBin1D]},
                    PutsE["injectedOptions:\n",{injectedOptions}, LogLevel->3];
                    Map[
                         GetDiffusionInBin1D[rwData, dt, {#[[1]]-#[[2]]/2,#[[1]]+#[[2]]/2},{cellMin,cellMax},injectedOptions]&
                         ,bins]
                ]
            ] (*end if -- no semicolon here! as  the result of the Map / ParallelMap gets returned*)

        ]
    ];



(*GetDiffusionInBins1D*)
(*Calculates the diffusion coeficients in all bins of the cell.
 rwData --  Data of the diffusion process. A list of points {{t,x,y},...}
 dt     --  the timstep between two points in the units of time 
 binSpec -- specfication of the bins {{minX,maxX,dstepX},{minY,maxY,dstepY}}
 cellRange The periodic cell limits {{minx,minY},{maxX, maxY}. If Null then taken form binSpec}*)

Options[GetDiffusionInBins1D] := {"Parallel"->True,(*Use parallel functions*)
							   "Method"->Select, (*The method of binning. For now select is redone for each bin. GatherBy would bin the data only once, but is not yet implemented*) 
							   "CellRange"->Automatic (*cell range in {{MinX,MinY},{MaxX,MaxY}}. If automatic, then calculated from binsOrBinSpec*)
							   }~Join~Options[GetDiffusionInBin1D];
Attributes[GetDiffusionInBins1D]={HoldFirst};
GetDiffusionInBins1D[rwData_,dt_,binSpec_,opts:OptionsPattern[]] :=
Block[{$VerbosePrint=OptionValue["Verbose"], $VerboseLevel=OptionValue["VerboseLevel"],$VerboseIndentLevel=$VerboseIndentLevel+1}, 
    Module[ {},
            Puts["********GetDiffusionInBins1D********"];
            PutsOptions[GetDiffusionInBins1D,{opts},LogLevel->2];
            Switch[OptionValue@"Method",
            Select,(*then*)
            	GetDiffusionInBinsBySelect1D[rwData,dt,binSpec, FilterRules[{opts},Options@GetDiffusionInBinsBySelect1D]],
            GatherBy, (*then*)
            	Assert[False, "GatherBy not yet implemented as method in GetDiffusionInBins1D"],
            _,(*else*)
            	Assert[False,"Wrong method "<>ToString@OptionValue@"Method"<>"in GetDiffusionInBins1D"]
            ]
        ]
    ];

GetDiffusionInBins1D::wrongargs="Wrong arguments for GetDiffusionInBins1D `1` ";  
GetDiffusionInBins1D[args___]:=(Message[DiffusionNormalForm::wrongargs,Shallow@args];$Failed);  

ClearAll[GetStepsHistogramDiffusion1D];
Options@GetStepsHistogramDiffusion1D={"binNum"->30};

GetStepsHistogramDiffusion1D[Dx_,dt_:1,ds_:1,opts:OptionsPattern[]]:=
Block[{sx, pdf, binN, points,max, $VerboseIndentLevel=$VerboseIndentLevel+1},
    Puts["***GetStepsHistogramDiffusion***"];
    PutsF["Dx: ``; stride: ``",Dx,ds,LogLevel->2];
    PutsOptions[GetStepsHistogramDiffusion1D,{opts}];
    
    binN=OptionValue@"binNum";
    sx=Sqrt[2*Dx*dt*ds];
    pdf=PDF@NormalDistribution[0,sx];
    (*3 sigma is 99.7% of area*)
    max=3*sx;
    points=Range[-max,max,2*max/binN];
    N[{#,pdf@#}&/@points]
]


ClearAll@GetDiffusionInfoForBinFromParameters1D;
GetDiffusionInfoForBinFromParameters1D[{x_,dx_}, timestep_,stride_,DiffX_,ReturnHistograms_:False]:=
With[{Dx=DiffX[x]},
	 {"Dx"->Dx, "sx"->Sqrt[2*Dx*stride*timestep],
	  "x"->x,"xWidth"->dx,"ux"->0, "dt"->timestep,
	  "StepsHistogram"->If[ReturnHistograms, GetStepsHistogramDiffusion1D[DiffX[x],timestep, stride]],  
	  "StepsInBin"->Null,"Stride"->stride, "PValue"->1, "IsNormal"->True,"xMinWidth"->dx,
	  
	  "DxError"->0, "sxError"->0, "StepsInBinError"->0,
      "xMinWidthError"->0, "uxError"->0, "PValueError"->0}
];


Options@GetDiffusionInfoFromParameters1D = {
               "Verbose":>$VerbosePrint,  (*Log output*)
			   "VerboseLevel":>$VerboseLevel,(*The amount of details to log. Higher number means more details*)
               "ReturnStepsHistogram"->False, (*Returns The PDF plot.*)
               "Parallel" -> True
}

GetDiffusionInfoFromParameters1D[binsOrBinspec_, timestep_?NumericQ, stride_?NumericQ, DiffX_,opts:OptionsPattern[]]:=
Block[{$VerbosePrint = OptionValue["Verbose"], $VerboseLevel = OptionValue["VerboseLevel"], $VerboseIndentLevel = $VerboseIndentLevel+1}, 
    Module[{bins},
        Puts["********GetDiffusionInfoFromParameters1D********"];
        (*PutsOptions[GetDiffusionInfoFromParameters1D,{opts},LogLevel->2];  *)      
        bins=GetBinsFromBinsOrSpec1D@binsOrBinspec;
        GetDiffusionInfoForBinFromParameters1D[#, timestep, stride,DiffX,OptionValue@"ReturnStepsHistogram"]&/@bins     
    ]
]     


GetDiffusionInfoFromParameters1D[binsOrBinspec_,timestep_?NumericQ, strides_List, DiffX_,opts:OptionsPattern[]]:=
Block[{$VerbosePrint = OptionValue["Verbose"], $VerboseLevel = OptionValue["VerboseLevel"],  $VerboseIndentLevel=$VerboseIndentLevel+1}, 
    Block[{bins, bin, stride (*just for syntax higlighting in WB*), tabelF = If[OptionValue@"Parallel", ParallelTable, Table]},
        Puts["********GetDiffusionInfoFromParametersWithStride1D********"];
        (*PutsOptions[GetDiffusionInfoFromParameters1D,{opts},LogLevel->2];  *)
        bins=GetBinsFromBinsOrSpec1D@binsOrBinspec;
        With[{iDiffX=DiffX,returnHistograms=OptionValue@"ReturnStepsHistogram"},
        tabelF[
            GetDiffusionInfoForBinFromParameters1D[bin, timestep, stride,iDiffX,returnHistograms],
        {bin,bins},{stride,strides}]
        ]      
    ]
]  


ClearAll@AverageOneDiffBin;
(*Given a list of diff bins, returns the averages and std errors of Quantities*)

AverageOneDiffBin[listOfDiffBins_,Quantities_]:=
Block[{result, quantity, quantityErr, tmpvals, mean, stderr,i},
   (*result=First@listOfDiffBins;*)
   result=DeleteDuplicates[Flatten[listOfDiffBins],First[#1] === First[#2]&];
   Table[
      quantityErr=quantity<>"Error";
      tmpvals=GetValues[Evaluate@quantity,listOfDiffBins];
      (*Take only numeric values*)
      tmpvals=Cases[tmpvals, _?NumericQ]; 
      If[Length@tmpvals<=1
      ,(*then*)
          mean=stderr=Missing["To few points in bin"];
      ,(*else*)
          mean=Mean@tmpvals; stderr=StandardDeviation@tmpvals;
      ];

      result=result/.(Rule[quantity,_]->Rule[quantity,mean]);
      (*delete it just in case, because not all diffs allready have a diff error*)
      result=DeleteCases[result, Rule[quantityErr,_]];
      AppendTo[result,  Rule[quantityErr,stderr]];
      
        ,{quantity,Quantities}];
         
    (*If we request Dx, Dy, and Da then add the components of the tensor and their errors*)
	If[And @@ (MemberQ[Quantities, #] & /@ {"Dx", "Dy", "Da"}),
	 tmpvals = GetValues[{"Dx", "Dy", "Da"}, listOfDiffBins];
	 (*Get the diff tensors componets Dxx, Dxy and Dyy*)
	 tmpvals = 
	  Flatten[Get2DCovarianceFromDiff[#]][[{1, 2, 4}]] & /@ tmpvals;
	 (*Take only numeric values*)
	 tmpvals = Select[tmpvals, VectorQ[#, NumberQ] &];
	 
	 If[Length@tmpvals <= 1,(*then*)
	  mean = stderr = ConstantArray[Missing["To few points in bin"], 3];
	  ,(*else*)
	  mean = Mean@tmpvals; stderr = StandardDeviation@tmpvals;];
	 
	 Table[
	  AppendTo[result, Rule[{"Dxx", "Dxy", "Dyy"}[[i]], mean[[i]] ] ];
	  AppendTo[result, Rule[{"DxxError", "DxyError", "DyyError"}[[i]], stderr[[i]] ] ];
	  , {i, 3}];
	];
   result
];

ClearAll@EstimateDiffusionError1D   
Options@EstimateDiffusionError1D={
            "Quantities"->{"Dx","Dy","Da"} 
            };

EstimateDiffusionError1D::usage="EstimateDiffusionError1D[listOfDiffs] take a list of diffusions (must have same bins) and 
calculates the averages and standard deviations for the given list of quantities (for example Dx, Dy...). 
Returns a diffusions list, where Dx->Avg[{Dx...}] and DxError->StDev[{Dx...}]"


EstimateDiffusionError1D[diffs:listOfdiffInfosWithStride,opts:OptionsPattern[]]:=
Block[ {$VerboseIndentLevel = $VerboseIndentLevel+1, binIndex, q, strideIndex,
        binNum (*Number of bins in one diffusion set*),strideNum (*number of strides*),
        quan, 
        result (*Diff set for results*)},
    Puts["***EstimateDiffusionError1D****"];
    PutsOptions[EstimateDiffusionError1D, {opts}, LogLevel -> 2];   
    
    quan = OptionValue@"Quantities";
    
    
    (*the dimensions describe : {set, bins, stride, diffRules}. diffRules is given only if all diff sets have the same umber of rules "Dy"->_ etc...*)
    binNum=Dimensions[diffs][[2]];
    strideNum=Dimensions[diffs][[3]];

    Table[AverageOneDiffBin[diffs[[All,binIndex,strideIndex]],quan],{binIndex,binNum},{strideIndex,strideNum}]
   
];


ClearAll@GetDiffusionsRMSD1D   
Options@GetDiffusionsRMSD1D={
                DistanceFunction->EuclideanDistance,
                "ReturnErrors"->False
            };

GetDiffusionsRMSD1D::usage="GetDiffusionsRMSD1D[diffs1, diffs2] takew two sets of diffusions (must have same bins) and 
calculates the RMSD between all the bins. The distance function used on the covariance tensors can be given as an option. Defaults to EuclidianDistance . 

Returns the RMSD."

GetDiffusionsRMSD1D[diffs1:diffInfos,diffs2:diffInfos,opts:OptionsPattern[]]:=
Block[ {$VerboseIndentLevel = $VerboseIndentLevel+1,i,covars1,covars2,rmsdList,df=OptionValue@DistanceFunction},
    Puts["***GetDiffusionsRMSD1D****"];
    PutsOptions[GetDiffusionsRMSD1D, {opts}, LogLevel -> 2];       
    If[Length@diffs1=!=Length@diffs2,
       Throw@StringForm["Number of bins in first and second diffusion set must be the same ``=!=``",Length@diffs1,Length@diffs2]
      ];
    
     
     (*devided by two since it has 2*sigma in the definition of the CovarianceTensor. devided by 3 to get per component deviation*)
     covars1=(Get2DCovarianceFromDiff/@GetValues[{"Dx","Dy","Da"},diffs1])/2;
     covars2=(Get2DCovarianceFromDiff/@GetValues[{"Dx","Dy","Da"},diffs2])/2;
     
        
     (*Handle missing casses*)
     (*For now just replace with 0
     covars1=covars1/.Missing[___]->0;
     covars2=covars2/.Missing[___]->0;*)
     rmsdList=Transpose@{covars1,covars2};        
     
     (*Filter missing*)
     (*Select only tensors that both have only numeric values*)
     rmsdList=Select[rmsdList,ArrayQ[#, _, NumericQ]&];
     If[Length@rmsdList===0, Return[Missing["To little points with valid diffusions"]]];
     rmsdList=df[#[[1]] , #[[2]] ]&/@rmsdList; 
     If[OptionValue["ReturnErrors"],
            {Mean@rmsdList, (* Percentiles corresponding to +-sigma*)
                {Mean@rmsdList-Quantile[rmsdList, 25/100, {{1/2, 0}, {0, 1}}], Mean@rmsdList-Quantile[rmsdList, 75/100, {{1/2, 0}, {0, 1}}]}}
        
     ,(*else*)        
        Mean@rmsdList
     ]
];
End[]

EndPackage[]

 