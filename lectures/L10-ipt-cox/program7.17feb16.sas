*program7.1feb16, Cox model and IP-weighted Cox model;

*Set some options;
options nocenter pagesize=60 linesize=80 nodate pageno=1;

*Set log and output to clear on each run;
dm log "clear;" continue; dm out "clear;" continue;

*Set a directory pointer;
%let dir = D:\dropbox\Cole\Teaching\EPID722\2016;
*%let dir = Y:\Cole\Teaching\EPID722\2016;

*Read ASCII file;
data a;
	infile "&dir\hividu15dec15.dat"; 
	input id 1-4 idu 6 white 8 age 10-11 cd4 13-16 drop 18 delta 20 @22 art 6.3 @29 t 6.3;
	
*Look at data, again;
proc means data=a n mean sum min max; 
	var delta t drop idu white age cd4;
	title "Time from 12/6/95 to AIDS or death in WIHS";

*Crude Cox model;
proc phreg data=a;
	model t*delta(0)=idu/rl ties=efron;
	*default is ties=breslow, ties=efron is better;
	ods select modelinfo fitstatistics parameterestimates;
	*this ods statement makes the print out nicer;
	title "Crude Cox model";

*Assess PH assumption;
*First look at plot of log H(t) by t;
proc phreg data=a noprint;
	model t*delta(0)=;
	strata idu;
	baseline out=b cumhaz=caph/method=pl;
data b; set b; if caph>0 then logcaph=log(caph);
ods listing gpath="&dir\";
ods graphics/reset imagename="logcumhaz" imagefmt=jpeg height=8in width=8in;
proc sgplot data=b noautolegend;
	title "log H(t) by time";
	step x=t y=logcaph/group=idu;
*Second test product of idu and t;
proc phreg data=a;
	model t*delta(0)=idu idut/rl ties=efron;
	idut=idu*t;
	ods select modelinfo fitstatistics parameterestimates;
	title "Crude Cox model, testing PH assumption";
run;
*Adjusted Cox model;
proc phreg data=a;
	model t*delta(0)=idu age white cd4/rl ties=efron;
	ods select modelinfo fitstatistics parameterestimates;
	title "Adjusted Cox model";

*Crude Cox model by hand;
*Get KM estimators of survival functions for each treatment group;
proc phreg data=a noprint;
	model t*delta(0)=;
	strata idu;
	baseline out=b survival=s/method=pl;
	output out=c(keep=idu t n) atrisk=n/method=pl;
*Merge together survival data with numbers at risk;
proc sort data=b;
	by idu descending s;
proc sort data=c nodups; by idu t;
data c; set c; by idu t; if first.t;
data d; merge b c; by idu t; if s>.;
*Calculate the log hazard functions;
*This is a fairly complicated program, but largely repeats last session;
data d(drop=chm1 sm1 tm1) avg(keep=avg0 avg1);
	set d end=end; 
	by idu descending s;
	retain chm1 0 sm1 1 tm1 0 sum0 0 sum1 0 count0 0 count1 0;
	if t=0 then do; 
		d=0; chm1=0; sm1=1; tm1=0; n=.;
	end;
	deltat=t-tm1; 
	if s>0 then ch=-log(s);
	y=round((ch-chm1)*n,1);
	if deltat>0 then h=y/(n*deltat);
	label n=;
	logh=log(h);
	if idu=0 and logh>. then do; count0=count0+y; sum0=sum0+logh; end;
	else if idu=1 and logh>. then do; count1=count1+y; sum1=sum1+logh; end;
	output d;
	chm1=ch; sm1=s; tm1=t;
	if end then do; avg0=sum0/count0; avg1=sum1/count1; output avg; end;
ods listing gpath="&dir\";
ods graphics/reset imagename="Hazards" imagefmt=jpeg height=8in width=8in;
proc sgplot data=d noautolegend;
	title "log hazard functions";
	loess x=t y=logh/smooth=.6 group=idu;

*Calculate the hazard ratio;
data avg; set avg;
	beta=avg1-avg0; *this is the beta coefficient from a Cox model, almost;
	hr=exp(beta);
proc print data=avg noobs; var avg0 avg1 beta hr; title "Hazard ratio by hand";

****OPTIONAL;
*Crude Cox model by IML;
proc iml; 
	use a; 
	title "Semiparametric Cox model, via IML";
	read all var {t} into t; 
	read all var {delta} into delta; 
	read all var {idu} into x;
	n=nrow(t); k=ncol(x); y=j(n,n,0); events=sum(delta);
	do i=1 to n; 
		do j=1 to n; 
			if t[i,]<=t[j,] then y[j,i]=1; 
		end; 
	end;
	start lik(b) global (delta,x,y); 
		ll=sum(delta#(x*b`-(log(exp(x*b`)`*y))`)); return(ll); 
	finish lik;
	b0={0};
  	var={"idu"};
  	optn={1 0};
  	call nlpnms(rc,bres,"lik",b0,optn);
  	bopt=bres`;
  	logL=round(lik(bopt`),1e-3);
  	null=round(lik(0),1e-3);
  	aic=round(-2*logL+2*k,1e-3);
  	bic=round(-2*logL+k*log(n),1e-3);
  	if rc<0 then print "Convergence failed"; 
	else if rc>0 then print "Model Fit",, Null logL AIC BIC Events N;
	call nlpfdd(ll,g,h,"lik",bopt);
  	cov=-inv(h);
  	seb=round(sqrt(vecdiag(cov)),1e-5);
  	b=round(bopt,1e-5);
  	wald=round((b/seb)##2,1e-5);
  	pvalue=round(1-cdf("chisquared",wald,1),1e-5);
  	print "MLEs",, var b seb wald pvalue;
  	hr=round(exp(b[1,]),1e-3); 
	lo=round(exp(b[1,]-1.96*seb[1,]),1e-3); 
	hi=round(exp(b[1,]+1.96*seb[1,]),1e-3);
  	print "RH and 95% CI",, var hr lo hi;
quit; run;
****END OPTIONAL;

*IP-weighted Cox model;
*Confounding weights;
proc logistic data=a desc noprint; model idu=; output out=n p=n;
proc logistic data=a desc noprint; model idu=white age cd4; output out=d p=d;
data c; merge a n d;
	if idu then w=n/d;
	else w=(1-n)/(1-d);
	label n= d=;
	drop _level_;

*IP-censoring weights;
data c; set c; retain z 1;
proc univariate data=c noprint; where drop=1; var t;
	output out=q pctlpts=20 40 60 80 pctlpre=p;
data q; set q; p0=0; p100=10; z=1;
data e; merge c q; by z;
	array j{6} p0 p20 p40 p60 p80 p100;
	do k=1 to 5;
		in=j(k);
		if j(k)<t<=j(k+1) then do; 
			out=t; 
			delta2=delta; *make a time-varying event indicator;
			_drop=drop; *make a time-varying drop indicator;
			output; 
		end;
		else if j(k+1)<t then do; out=j(k+1); delta2=0; _drop=0; output; end;
	end;
proc sort data=e; by id in;
proc logistic data=e noprint; 
	class in/param=ref desc; 
	model _drop=in;
	output out=nm2(keep=id _drop nm2 in out) prob=nm2;
proc logistic data=e noprint; 	
	class in/param=ref desc; 
	model _drop=in idu white age cd4;
	output out=dn2(keep=id _drop dn2 in out) prob=dn2;
proc sort data=nm2; by id in; 
proc sort data=dn2; by id in; 
data f; merge e nm2 dn2; by id in; retain num den;
	if first.id then do; num=1; den=1; end;
	num=num*nm2;
	den=den*dn2;
	if _drop then w2=(1-num)/(1-den); else w2=num/den;
	w3=w*w2;
	label nm2= dn2=;
proc means data=f; 
	var w w2 w3 num den;
	title "IP-weights";

*Check crude model is same with counting-process data input (i.e., entry and exit times);
proc phreg data=f;
	model (in,out)*delta2(0)=idu/rl ties=efron;
	ods select modelinfo fitstatistics parameterestimates;
	title "Check crude model";

*IP-weighted Cox model, with counting-process data input;
*Use robust variance;
proc phreg data=f covs;
	id id;
	model (in,out)*delta2(0)=idu/rl ties=efron;
	weight w3;
	ods select modelinfo fitstatistics parameterestimates;
	title "IP-weighted Cox model";

run; quit; run;
