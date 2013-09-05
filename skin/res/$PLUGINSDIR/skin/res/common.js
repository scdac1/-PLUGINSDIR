//Setup a generic error handler.
window.onerror=function(msg,uri,line){
    uri=uri || "???";
    line=line || "--";
    msg = msg || "<NO MESSAGE>";
    issueCommand("debug/log",uri + ":" + line + ":" + msg);
    if(DEBUG_MODE){
        alert("Exception(Global):"+ msg);
    }
    try{
    console.log("ERROR",msg,url,line);
    }catch(_){
    }

    return true;
}
var isWindow=function(elt){
        if(elt === window) return true;
        if(elt && elt.document==window.document) return true;
        if(typeof(elt) === "object") return elt == window;
        return false;
    }
var ExceptionWrap=function(f,tag){
    return function(a,b,c,d,e){
        try{
            return f.call(this,a,b,c,d,e)
        }catch(e){
            if(DEBUG_MODE){
                alert("Exception:" + e.message );
            }
            issueCommand("debug/log","Exception:" + (tag || "-") +  e.message)
        }
        return null;
    }
    }

    var debug_log=function(x){
        if(typeof(issueCommand) ==='undefined'){
            if(console && console.log) console.log(x);
            return;
        } 
        issueCommand("debug/log",x);
    }
var debug_trace=function(x){
        if(typeof(issueCommand) ==='undefined'){
            if(console && console.log) console.log(x);
            return;
        } 
        issueCommand("debug/trace",x);
    }

var appNumber=0;
var BundleData;
var AppData;
var EnvData;
var FirstBundle=0;
var CurrentBundle=0;
var SkinData;
var customFeatures=0;
var footerHeight=63;
var DEBUG_MODE=false;
var STATE_INSTALLING=2,STATE_OFFERING=1,STATE_COMPLETE=3,STATE_CANCEL=4,STATE_LOADING=0,
STATE_UNINSTALL=5;


METRIC_SEQUENCE="metrics"


var hasKo=typeof(window.ko) !== 'undefined';

function loadKoModel(){

    //Special Knockout Methods
    if(!ko.subscribable.fn.latched){
        ko.subscribable.fn.latched=function(){
            var value=ko.observable(this());
            this.subscribe(function(x){
                value(x);
            })
            value.equalityComparer = function(a,b){
                return  ko.observable.fn.equalityComparer(a,b) ||  a===b;
            }
            return value;
        }
    }

    ko.bindingHandlers['visibility']={
        init:function(){
        },
        update:function(element,valueAccessor,allBindingsAccessor){
            var $this=$(element),
            visibility=ko.utils.unwrapObservable(valueAccessor()),
            newval=visibility?"visible":"hidden";
            $this.css("visibility",newval);
        }
    };
    
    ko.bindingHandlers['heightOf'] = {
        init: function(){
        },
        update: function(element,valueAccessor,allBindingAccessors){
            var val=valueAccessor(); 
            window.setTimeout(function(){
                var elt=$(element);
                val(elt.is(":visible")?elt.outerHeight():0)
            },100)
        }
    }

    var _xmlTextAccessor=function(name){
        return function(){
            return this.bundle[name] && this.bundle[name]._body_
        }
    }

    var _xmlAttrAccessor=function(name){
        return function(){
            var a=this.node._a_;
            if(!a) return null;
            return a[name]
        }
    }
    
    var Bundle=window.Bundle=function(src){
        if(isWindow(this)) return new Bundle(src);
        this.bundle=src || {}; 
        this.features=ko.computed({read:function(){
                var self=this.bundle;
                return $.map(this.bundle.Feature,function(feat,index){
                    if(feat.isDirective || feat.isHidden) return [];
                    return new Feature(self,index);
                });
        },owner:this,deferEvaluation:true});
        return this;
    }
    
    Bundle.prototype={
        productName:_xmlTextAccessor("ProductName"),
        customCss:_xmlTextAccessor("CustomCss"),
        feature:function(idx){
            return  new Feature(this.bundle,idx);
        }
    };

    /**
     * Model for Feature $index in the Bundle $bundle;
     */
    var Feature=window.Feature=function($bundle,$index){
        if(isWindow(this)) return new Feature($bundle,$index);
        this.node=$bundle.Feature[$index]; 
        this.checked=window.model.featureState($index,$bundle)
    };
    Feature.prototype = {
        name:_xmlAttrAccessor("Name")
    };


    var InstallModel=window.InstallModel=function(){
        var self=this;
        this.CurrentBundle=ko.observable(0);
        this.BundleData=ko.observableArray([]);
        this.AppData=ko.observable({});
        this.SkinData=ko.observable({}); 
        this._internalUpdate=ko.observable(0);
        this._internalMetricUpdate=ko.observable(0);
        this.singleProgressBar=ko.computed({
                owner:this ,
                read:function(){
                    this.AppData(); //Dependency
                    return hasSingleProgressBar()
                },
                deferEvaluation:true 
        });
        this.VisibleBundles=ko.computed({
                read:function(){
                    this._internalUpdate(); //establish a dependency
                    return $.grep(self.BundleData(),function(v,k){
                        return v!=null && v._willDisplay_ == 1;
                    });
                },owner:this
        });

        this.InstallingBundles=ko.computed({
                read:function(){
                    this._internalUpdate(); //establish a dependency
                    return $.grep(self.BundleData(),function(v,k){
                        return v!=null && v._willInstall_== 1;
                    });
                },owner:this
        });

        this.InstalledBundles=ko.computed({
                read:function(){
                    this._internalUpdate(); //establish a dependency
                    return $.grep(self.BundleData(),function(v,k){
                        return v!= null && v._installed_ == 1;
                    });
                },owner:this
        });
        this.currentBundleData=ko.computed(function(){
            if(self.BundleData().length == 0) return null;
            return self.BundleData()[self.CurrentBundle()];
        });

        this.productEulaUrl=ko.computed(function(){
            var data=self.currentBundleData();
            //alert("Current Bundle :" + self.CurrentBundle() + " -> " +
            //     self.currentBundleData());
            if(!data) return "";
            return data.ProductEula._body_;
        });


        this.leadProduct=ko.computed(function(){
            if(self.VisibleBundles().length == 0) return null;
            return self.VisibleBundles()[0];
        });
        this.isLeadProduct=ko.computed({read:function(){
                return this.leadProduct() == this.currentBundleData()
        },owner:this,deferEvaluation:true});


        this.state=ko.observable(STATE_LOADING)
        this.stateHasEula = ko.computed({read:function(){
                switch(this.state()){
                case STATE_LOADING:
                case STATE_OFFERING:
                    return true;
                }
                return false;
        },deferEvaluation:true,owner:this});
        /*this.state=ko.computed({read:this._state,
         write:this._state}).extend({throttle:50});;*/
        this.postOfferSteps=ko.observable(2); //Install and  Complete page.
        this.eulaLoaded=ko.observable(false);
        this.installThisOne=ko.observable("yes");
        this.canPause=ko.observable(false);
        this.isPaused=ko.observable(false);
        this.isOffer=ko.computed(function(){return self.state() == STATE_OFFERING; });
        this.isInstalling=ko.computed(function(){return self.state() == STATE_INSTALLING; });
        this.isComplete=ko.computed(function(){return self.state() == STATE_COMPLETE; });
        this.isCancel=ko.computed(function(){return self.state() == STATE_CANCEL; });
        this.isLoading=ko.computed(function(){return self.state() ==STATE_LOADING; });
        this.isInstallNow = ko.computed(function(){
            return self.isComplete();
        });
        //isDlcomOpen -> 
        //for download.com a lead product with a single <File/> entry 
        //with Extract at Installation will trigger the open action.
        this.isDlcomOpen = ko.computed({read:function(){
                if(!this.isComplete()) return false;
                try{
                    var primary=this.leadProduct();
                    //Non blank product binary then no dice.
                    if(primary.ProductBinary._body_ != "") return false;
                    if(primary.File.length != 1 ) return false;
                    //If the action is Extract at installation
                    if(primary.File[0]._a_.Action.toLowerCase() == "Extract at Installation".toLowerCase()){
                        return true;
                    }
                }catch(_){
                    return false;
                }
                return false;
        },owner:this,deferEvaluation:true });
        //Should the "Show" button be used instead of the Install Now  button
        this.isDlcomShow= ko.computed({read:function(){
                if(!this.isComplete()) return false;
                try{
                    var primary=this.leadProduct();
                    //Non blank product binary then no dice.
                    if(primary.ProductBinary._body_ != "") return false;
                    if(primary.File.length != 1 ) return false;
                    //If the action is Copy at installation
                    if(primary.File[0]._a_.Action.toLowerCase() == "Copy at Installation".toLowerCase()){
                        return true;
                    }
                }catch(_){
                    return false;
                }
                return false;
        },owner:this,deferEvaluation:true });


        this.optInStyle = ko.computed(function(){
        });
        this.isPrimary=ko.computed(function(){
            var app=self.currentBundleData();
            if(!app) return false;
            //alert("is Primary - " + app.isPrimary);
            return app.isPrimary;
        });
        this.carrotIcon=ko.computed({read:function(){
                var appData=this.AppData();
                if(appData.CarrotIcon && AppData.CarrotIcon._body_){
                    return appData.CarrotIcon._body_;
                }
                return null;
        },deferEvaluation:true,owner:this});

        this.customCss=ko.computed(function(){
            var bundle=self.currentBundleData();

            var css=(bundle && bundle.CustomCss && bundle.CustomCss._body_) || "";
            //if(css.length > 0 ) alert(css);
            return css;
        });
        this.customCss.subscribe(function(){
            $(".eula-holder").attr("style",self.customCss())
        });
        //Has custom Features
        this.hasCustomFeatures=ko.observable(false);
        this.CurrentBundle.subscribe(function(x){
            self.eulaLoaded(false);
            self.hasCustomFeatures(false);
            var bundle=self.BundleData()[x];
            if(bundle ==null) return; //Skip the nulls
            /*alert("Would|" + bundle.bundleIndex + "|install|"  + self.CurrentBundle() + "| => " +  bundle._wouldInstall_);
             while(true){
             var x= window.prompt("What should I run")
             if(x == "stop") break;
             try{
             alert(">" + eval(x))
        }catch(e){
        }
        }*/
        switch(bundle._wouldInstall_){
        case -1:
        case  1: self.installThisOne("yes"); break;
        default:
            self.installThisOne("no");
            break;
        }
        });


        this.numSteps=ko.computed(function(){
            return self.VisibleBundles().length +self.postOfferSteps();
        });

        this.installPageNumber=ko.computed(function(){
            return self.numSteps()-1;
        });
        this.currentStep=ko.computed(function(){
            var idx=$.inArray(self.currentBundleData(),self.VisibleBundles());
            var num=self.numSteps();
            //Complete is last step
            if(self.isComplete()) return num;
            //Installing is second to last step
            if(self.isInstalling()) return  self.installPageNumber();
            //Other step are index of current bundle
            return idx+1;
        });

        this.applicationTitle=this.productName=ko.computed(function(){
            if(self.leadProduct() == null) return "";
            return self.leadProduct().ProductName._body_;
        });

        this.currentProductName=ko.computed(function(){
            var b=this.currentBundleData();
            if(!b) return "";
            return b.ProductName._body_;
        },this);
        this.startTime = ko.observable();
        this.toDownload = ko.observable(1);
        this.downloaded = ko.observable(0);
        //Index into the big downloads step.
        this.dlLastBigStep = ko.observable(0);
        //The download steps we have seen.
        this.dlStepsSeen= {};
        //The actual top level installation steps.
        this.dlNumBigSteps =ko.computed(function(){
            return self.AppData().TotalInstallSteps || 0;
        });
        this.dlLastBundleIdx=ko.observable();
        this.dlLastBundle = ko.computed({owner:this,
                read:function(){
                    try {
                        var ret=Bundle(this.BundleData()[this.dlLastBundleIdx()]);
                        return ret;
                    }catch(_){ 
                    return Bundle({});
                    }
        },deferEvaluation:true});
        this.dlLastBundleName = ko.computed({
                owner:this,
                read:function(){  return this.dlLastBundle().productName(); },
                deferEvaluation:true
        })
        this.globalProvider=null;

        this.dlLastActivity = ko.computed({
                owner:this,deferEvaluation:true,
                read:function(){
                    try{
                        var provider=this.globalProvider || new StatusProvider(this.VisibleBundles()[0]);
                        this.globalProvider=provider;
                        return provider.activity();

                    }catch(_){
                        return null;
                    }
                }
        });

        this.downloadProgress= ko.computed(function(){

            var pcnt=self.downloaded()/(self.toDownload()+1)*100;
            if(self.dlNumBigSteps() > 0  && ! self.AppData().TotalDownloadSize ){
                //If there is big step information
                //We will break each big step into a large segment
                //and fill the progress of it using the download progress information
                var pcntPerStep= 100/self.dlNumBigSteps();
                pcnt=(pcntPerStep * (self.dlLastBigStep()-1)) + ((pcnt/100) * pcntPerStep);
            }
            var str=Math.min(100,Math.max(0,pcnt.toFixed(2))) + "%";
            return str;
        });

        this.toDownloadMb=ko.computed(function(){
            return toMB(self.toDownload());
        });
        this.toDownloadHuman=ko.computed(function(){
            return toHuman(self.toDownload());
        });

        this.downloadedMb=ko.computed(function(){
            return toMB(self.downloaded());
        });
        this.downloadedHuman=ko.computed(function(){
            return toHuman(self.downloaded());
        });
        // Download Rate
        this.downloadRateRaw=ko.computed(function(){
            if(self.startTime() == null && self.downloaded() > 1){
                self.startTime(new Date());
            }
            if(self.startTime() == null) return;
            var secDiff=new Date().getTime() -  self.startTime().getTime();
            secDiff=secDiff/1000

            return self.downloaded()/secDiff;
        });

        this.downloadRate=ko.computed({owner:this,
                read:function(){
                    return toMB(this.downloadRateRaw()) + "MB/s"
                } 
        });

        this.downloadRateHuman=ko.computed({owner:this ,
                read:function(){
                    return  toHuman(this.downloadRateRaw()) + "/s";
                }
        });

        this._sequence=0; //metric sequence
        this.showMetrics=ko.observable(false);//Default is to hide metrics 
        this.metrics=ko.computed({read:function(){
                this._internalMetricUpdate(); //establish a dependency
                return getInstallMetrics();
        },owner:this,deferEvaluation:true});
        //Custom Parameters
        this.customParameters=ko.computed({
                owner:this,
                read:function(){
                    var c={};
                    try{
                        var b=this.currentBundleData(),
                        data=b.CustomParameter;
                        for(var x in data) {
                            var node=data[x];
                            c[node._a_.Name]=node._body_;
                        }
                        return c;
                    }catch(_){
                    }
                    return c;
        },deferEvaluation:true });
        this.haveIframe=ko.computed({owner:this,
                read:function(){
                    return !this.isLeadProduct() && this.stateHasEula()
        },deferEvaluation:true}).extend({throttle:50});
        this.ui=ko.computed({owner:this,
                read:function(){
                    var ret={}
                    ret.isLeadProduct=this.isLeadProduct();
                    ret.productEulaUrl=this.productEulaUrl();
                    ret.customParameters = this.customParameters();
                    ret.isPrimary = this.isPrimary()
                    ret.isLoading = this.isLoading()
                    ret.isOffer = this.isOffer()
                    ret.hasEula= this.stateHasEula();
                    return ret;
        },deferEvaluation:true}).extend({throttle:50});


        this.progressCache=ko.observable({});
        this.isUninstaller=ko.computed(function(){
            return this.state() ==  STATE_UNINSTALL;
        },this);
        //Skip All handling
        this.showSkipAll=ko.computed({
                read:function(){
                    this.internalUpdate();//Internal Update Linkage
                    if(!this.isOffer()) return false;
                    var appData=this.AppData(),
                    bundle=this.currentBundleData(),
                    skipAllPosition=(appData.SkipAllPosition && appData.SkipAllPosition._body_),
                    skipAllVisible=false;
                    if(skipAllPosition && skipAllPosition.length>0){
                        skipAllVisible=showSkipAll(skipAllPosition,bundle)
                    }
                    //alert("SkipAll -> " + skipAllPosition + "/" + skipAllVisible + "/" + bundle.advertiserIndex )
                    return skipAllVisible;
                },
                owner:this,
                deferEvaluation:true
        });
        //Multi Progress Switch.
        this.multiProgress=ko.computed({read: function(){
                var ret=this.SkinData().multi_progress == true;
                return ret;
        },owner:this,deferEvaluation:true });

        /**
         * Has feature Bar 
         */
        this.hasFeatureBar=ko.computed({read:function(){
                return this.currentBundleData() && this.eulaLoaded() && !this.hasCustomFeatures();
        },owner:this})

    }
    $.extend(InstallModel.prototype,{
            internalUpdate:function(){
                this._internalUpdate(this._internalUpdate()+1);
            },
            updateInstallLine:function(idx,status,originalIdx){
                var bundle=this.BundleData()[originalIdx -1];
                if(bundle == null) return;
                var key="_"  + (originalIdx-1),
                cache=this.progressCache();
                this.dlLastBundleIdx(originalIdx-1);
                provider= cache[key] || this.globalProvider,
                params=INSTALL_DATA[status];
                if(!provider) return;
                switch(status){
                case "Downloaded":
                    if(provider){
                        log("Done -> " + originalIdx);
                        provider.activity("Downloaded");
                        provider.done(true);
                    }
                    break;
                default:
                    if(params){
                        provider.activity(params[0]);
                    }
                }


            },
            updateProgress:function(idx,min,max,stepIdx,canPause){
                var bundle=this.BundleData()[idx-1];
                if(bundle == null) return;
                if(stepIdx ==  bundle.InstallStepIdx){
                    bundle.downloaded=min;
                    bundle.toDownload=max;
                }
                if(stepIdx >0){
                    this.dlLastBigStep(stepIdx);
                    this.dlStepsSeen["_" + stepIdx] = 1
                }
                //Process all the files
                $.each(bundle.File,function(_,f){
                    //If we have seen this step.
                    if(f.InstallStepIdx == stepIdx){
                        f.downloaded=min;
                        f.toDownload=max;
                        return false;
                    }
                });

                this.updateTotals();
                this.canPause(canPause==1);
            },
            updateDownloadRate:function(){
            },
            updateTotals:function(){
                var _min=0,_max=1;
                var self=this;
                $.each(this.InstallingBundles(),function(_,v){
                    var _initial=_min,_initialMax=_max;
                    _last=v._lastmindownload || 0;
                    _min = _min + (this.downloaded || 0)
                    _max = _max + (this.toDownload  || 1) ;
                    $.each(v.File,function(_,f){
                        if(f.downloaded) _min = _min + f.downloaded;
                        if(f.toDownload) _max = _max + f.toDownload;
                    });
                    //log("Updated -> " + [_min,_max,_initial,_last,v._downloadUpdate].join(","))
                    var dled=_min-_initial,
                    dlmax=(_max-_initialMax)
                    if(_min != _initial){ //Nothing changed for thos.
                        //Something changed
                        if (dled != _last ){
                            //log("Download Update");
                            var key="_"  + _,cache= self.progressCache(), 
                            provider= cache[key];
                            if(provider){
                                provider.downloaded(dled);
                                if(v.TotalBundleBytes){
                                    provider.toDownload(v.TotalBundleBytes);
                                }else provider.toDownload(dlmax);
                            }
                        }else {
                            //log("Unchanged");
                        }
                    }
                    v._lastmindownload=dled;
                });

                if(this.AppData().TotalDownloadSize) {
                    this.toDownload(this.AppData().TotalDownloadSize);
                }else this.toDownload(_max);
                this.downloaded(_min);
            },
            pauseDownload:function(){
                issueCommand("install/pause");
            },
            resumeDownload:function(){
                issueCommand("install/resume");
            },
            metricModeHandle:function(_,e){
                e=$.event.fix(e);
                if(!DEBUG_MODE) return;
                var _char=String.fromCharCode(e.keyCode);
                if(METRIC_SEQUENCE.charAt(this._sequence) == _char ){
                    this._sequence=this._sequence+1;
                }else{
                    this._sequence=0;
                }
                if(this._sequence ==  METRIC_SEQUENCE.length){
                    this._sequence=0;
                    this._internalMetricUpdate(this._internalMetricUpdate()+1);
                    this.showMetrics(true);
                }
            },getProductName:function(x){
                try{
                    return x.ProductName._body_;
                }catch(_){
                    return "";
                }
            },
            showProgressDetails:function(){return true; },
            doSkipAll:doSkipAll,
            hasSkipAll:ko.computed({
                    read:function(){
                        //Is skip all enabled
                        return hasSkipAll()
                    },deferEvaluation:true
            }), featureState:function(id,_bundle){
            var bundle=_bundle || this.currentBundleData();
            if(bundle == null) return false;
            //debug_log("State " + id + " for Bundle " + bundle.bundleIndex);
            var feature=null,feat=null;
            var featureIndex=null;
            if(typeof(id) === 'number'){
                featureIndex=id
                feat=feature=bundle.Feature[id]
            }else{
                for(var x in bundle.Feature){
                    var feat=bundle.Feature[x];
                    if(feat && feat._a_ && feat._a_.id == id){
                        feature=feat;
                        featureIndex=x;
                        break;
                    }
                }
                if(!feat) return false;
            }
            if (!feat._observable){
                feat._observable= ko.observable(feat._a_.InitialState == "checked");
                feat._observable.subscribe(function(x){
                    var newstate=feat._a_.InitialState=x?"checked":"unchecked";
                    issueCommand("bundle/featureState",[bundle.bundleIndex-1,featureIndex,newstate].join("|"));
                });
            }
            return feat._observable;
            },doThanks:function(){
                //thanks for the App
                issueCommand("app/thanks","");
            },doTrack:function(){
                issueCommand("app/track","");
            }
    })
    window.model = new InstallModel();
}
var  StatusProvider=function(bundle){
    this.bundle=bundle;
    this.done=ko.observable(this.bundle._prepareStatus_ == 'success');
    this.activity=ko.observable(getStatus(this.bundle));
}

var ProgressProvider=function(idx,blist){
    if(isWindow(this)){
        var key="_" + idx,
        progressCache=window.model.progressCache();
        if(typeof progressCache[key] === 'undefined'){
            progressCache[key]=new ProgressProvider(idx,blist);
        }
        return progressCache[key];
    }
    //log("Provider Cache [" + idx  + "]");
    var $root=window.model;
    StatusProvider.call(this,blist[idx]);
    this.changed=ko.observable(0);
    this.downloaded=ko.observable(0);
    this.toDownload=ko.observable(1);
    //log("Prepare Status for " + idx + " -> " + this.bundle._prepareStatus_ );
    this.startTime=ko.observable();
    var self=this;


  /*  this.bundle._downloadUpdate=function(min,max){
        log("Download Update :" + min  + " -> " + max);
        self.downloaded(min);
        self.toDownload(max||1);
    }*/

    this.isPaused= $root.isPaused;
    this.canPause= ko.computed({owner:this,
            read:function(){
                return this.downloaded()>0 && $root.canPause() && !this.done();
            }
    });
    this.downloadProgress=ko.computed({owner:this,
            read:function(){
                this.done();this.downloaded();this.toDownload();
                if(this.done()) return "100%";
                if(this.downloaded() == 0) return "0%";

                var pcnt=this.downloaded()/(this.toDownload()+1)*100;
                var str=Math.min(100,Math.max(0,pcnt.toFixed(2))) + "%";
                log("DownloadProgress:" + this.bundle.ProductName._body_  + " -> " + str);
                return str;
            }
    });
    this.showProgressDetails=ko.computed({owner:this ,
            read:function(){
                return this.downloaded() >0 &&  !this.done();
                //return this.downloaded() >0 && this.downloaded() < this.toDownload();
            }
    });
    this.downloadedHuman=ko.computed({owner:this,
            read:function(){
                var ret=toHuman(this.downloaded());
                log("Downloaded -> " + ret);
                return ret;
            }
    });
    this.toDownloadHuman=ko.computed({owner:this,
            read:function(){
                return toHuman(this.toDownload());
            }
    });

    // Download Rate
    this.downloadRateRaw=ko.computed({owner:this,
            read:function(){
                if(this.startTime() == null && this.downloaded() > 1){
                    this.startTime(new Date());
                }
                if(this.startTime() == null) return;
                var secDiff=new Date().getTime() -  this.startTime().getTime();
                secDiff=secDiff/1000

                return this.downloaded()/secDiff;
            }
    });

    this.downloadRateHuman=ko.computed({owner:this ,
            read:function(){
                return  toHuman(this.downloadRateRaw()) + "/s";
            }
    });
}

function setFirstBundle(idx){
    if(typeof idx != "undefined"){
        FirstBundle=idx;
    }
}
function setCurrentBundle(idx){
    window.CurrentBundle=CurrentBundle=idx;
    if(window.external){
        issueCommand("bundle/Current",idx);
    }
    if(hasKo) model.CurrentBundle(idx);
}

//Set the bundle data.
function setBundleData(data){
    BundleData=data;
    if(hasKo) window.model.BundleData(data);
}

function setEnvData(data){
    EnvData=data
}

function setAppData(data){
    AppData=data;
    //Carrot product has an icon
    if(!window.ko){
        //When we use knockout we wont put view logic in this code.
        if(AppData.CarrotIcon && AppData.CarrotIcon._body_){
            $("#logo").css("background-image","url(" + AppData.CarrotIcon._body_ + ")");
        }
        var skipAllPosition=AppData.SkipAllPosition && AppData.SkipAllPosition._body_;
        if(skipAllPosition && skipAllPosition.length >0){
            $("body").addClass("has-skip-all"); 
        }
    }
    if(hasKo){
        window.model.AppData(data);
        window.model.progressCache({});

    }
}

function setSkinData(data){
    SkinData = data;
    if(hasKo){
        window.model.SkinData(data);
    }
}

function setPauseState(isPaused){
    if(hasKo){
        window.model.isPaused(isPaused==1);
    }
}


var getCustomParameter=function(bundle,name){
    try{
        var found=null;
        $.each(bundle.CustomParameter,function(){
            if(!this._a_) return ;
            if(this._a_.Name == name){
                found =this._body_;
                return false;
            }
        });
        return found;
    }catch(_){
        return null;
    }
    }

/**
 * Return if a bundle requires a click to proceed.
 */
function requiresClick(bundle){
    return getCustomParameter(bundle,"requires-click") == "true"
    
}
var captionFunction=function(bundle){
    return bundle.ProductName._body_ || "Unknown"
}
function setCaptionFunction(x){
    captionFunction=x;
}

function renderBundle(bundle,idx){
    var eula=bundle.ProductEula._body_;
    $("#spnCaption").text(captionFunction(bundle));
    /*
     var frame=$(".eulaeiframe");
     var fParent=frame.parent();
     frame.remove();
     var frameHtml="<iframe  onload='onEulaLoaded()'" 
     + " frameborder='0' scrolling='no' class='pane' src='" + eula + "' ></iframe>";
     fParent.append(frameHtml);
     */
    //We will pass the BundleID in the hash.
    var frame=$("#frameEula");
    frame.attr("src",eula );
    frame.hide();
    //if(!frame.is(":visible")) frame.show();
    //alert("Eula is " + eula + "/" + document.location);
    $(".nofirst").attr('disabled',idx==FirstBundle?'disabled':'');
    /**
     * ake the decline button a bit more explicit.
     * We will hide it if 
     * 1. Product has an optin 
     * 2. Product is a primary product.
     */
    if(hasOptin()){
        $("#decline-button").hide();
    } else if(bundle.isPrimary === false){
        $("#decline-button").show();
    } else if( bundle.isPrimary === true ){
        $("#decline-button").hide();
    }else {
        $("#decline-button").show();
    }

    //Populate list of items.
    var itemlist="";
    var number=0;
    for(var i=0;i<idx;++i){
        var b=BundleData[i];
        if(b == null) continue;

        if(b._willInstall_ == 1){ 
            number+=1;
            if(name) itemlist=itemlist + "<li>" + number + ". " + b.ProductName._body_;
        }
    }
    $("#ulAccepted").show().html(itemlist);
    //Hide list of items for first offer
    $("#divAccepted")[idx==FirstBundle?'hide':'show']();
    //TODO/DONE: Handle  Features 
    $("#accept-button").focus();
    //Hide or show the back button.
    $("#back-button")[idx>FirstBundle?"show":"hide"]();
    //Update the steps
    var pc=$("#footer-steps .page-container"),
    pageNumText=pc.find("span.num-progress,div.num-progress"),
    realCount=0,realIdx=0,
    pageIcons=pc.find("span.pages");
    pc.show();
    pageIcons.html("");
    for(var i=0;i<BundleData.length;++i){
        var bndl=BundleData[i],
        state=(i<=idx)?"on":"off";
        if(bndl == null) continue;
        if(!bndl._willDisplay_) continue;
        realCount+=1;
        if(idx==i) realIdx=realCount;
        pageIcons.append($("<span class='page " + state + "' >&nbsp;</span>"))
    }
    pageNumText.text((realIdx) + " of " + realCount);

    //Handle Skip All
    var skipAllPosition=AppData.SkipAllPosition && AppData.SkipAllPosition._body_;
    var skipAllVisible=false;
    if(skipAllPosition){
        skipAllVisible=showSkipAll(skipAllPosition,bundle);
    }
    var items=$("#skipAll,#skip-all-button")
    //alert("Skip All Visible -> " + bundle.advertiserIndex +  "/" +  skipAllPosition + "/" + skipAllVisible + "/" + items.length);
    items[skipAllVisible?"show":"hide"]();
}

function getInstallMetrics(){
    var ret=issueCommand("install/metrics")
    try { 
        var resp=eval("(" + ret + ")"); 
        if(resp.entries) resp.entries.sort(function(x,y){
            if(x.start != y.start) return x.start - y.start;
            return x.end-y.end;
        });
        return resp
    }catch(_){
        return { "initial": 0 , entries: [] }
    }
}

function isHiddenContinuation(currentBundle,idx){
    try{
    var prev=BundleData[idx-1];
    if(prev ==null) return false;
    if(!currentBundle.isContinuation) return false; //Only work for continuations
    if(prev._willInstall_ == 1) return false; //Show if Prior is to be installled
    return true; // if its a continaution and the prior screen will NOT be installed we need to hide it
    }catch(_){
        debug_log("Bundle[" + idx + "] Error Processing Continuation:" + e.message); 
    }
    return false;
}

//Load the offer screen for a specific bundle
function offerBundle(idx,dir,check){
    updateBodyClass("offer"); 
    dir=dir||1;
    var bundle=BundleData[idx]
    var skipBundle=function(){ 
        //Skip the bundle we are currently on.
        if(dir ==1) {
            if(window.ko){
                nextBundle(false,idx);
            }else{
                nextBundle(false);
            }
        } else if(CurrentBundle>0){
            //If for some reason we cant get the previous bundle  t
            prevBundle(idx)
        }
    }
    //A Null bundle then we skip to the next one
    if(bundle == null){
        return skipBundle();
    }
    if(check){
        var ret=issueCommand("bundle/getProdState",bundle.bundleIndex-1);
        try{
            var resp=eval("(" + ret + ")"); 
            //Copy over fields
            $.each(["_willDisplay_","_willInstall_","isConsolidated","consolidated","advertiserIndex"],function(){
                if(typeof resp[this] != "undefined") {
                    bundle[this]=resp[this];
                }
            });
            if(hasKo){
                window.model.internalUpdate();
            }
        }catch(e){
        issueCommand("debug/log",e + "|" + e.message + "|" + ret);
        }

    }
    //Bundle is not to be shown then to offer it 
    //is to transition to the next bundle
    if(bundle._willDisplay_==0 || isHiddenContinuation(bundle,idx)){
        if(!window.ko){
            //We wont show bundles that dont have eulas loaded
            setCurrentBundle(idx);
        }
        return skipBundle(); 
    }
    var shown=parseInt(issueCommand("bundle/preOffer",bundle.bundleIndex));
    if(window.model && window.model.force){
        shown=true;
    }
    if(!shown && window.model){
        model.state(STATE_LOADING);
        return;
    }
    if(!window.ko){
        renderBundle(bundle,idx); 
    }else{
        model.state(STATE_OFFERING);
    }
    setCurrentBundle(idx);
    resetCustomFeatures();
}



function resetCustomFeatures(){
    try {
        window.external.issueCommand("bundle/resetCustomFeatures","");
    }catch(E){
    }
}

/**
* Called from a SUb Eula that has checkboxes embedded
*/
function setupCustomFeatures(subdoc){
    window.external.issueCommand("bundle/customFeatures","");
}

// Called from the nested EULA iframe when the feature element is clicked.
// <input type='checkbox' > is expected to have name='the designated feeature name'
function onFeatureChange(checkbox){
    var elt=$(checkbox);
    var name=elt.attr("name");
    var checked=elt.is(":checked");
    var bundle=BundleData[CurrentBundle];
    for(var x in bundle.Feature){
        var feat=bundle.Feature[x];
        if(feat._a_.id.toLowerCase()==name.toLowerCase()){
            var newState=feat._a_.InitialState=checked?"checked":"unchecked";
            //lower case string. comparison
            issueCommand("bundle/featureState",[bundle.bundleIndex-1,x,newState].join("|"));
            break;
        }
    }

}

window.onFeatureChange=onFeatureChange;


function hasCustomFeatures(){
    try{
        return window.external.issueCommand("bundle/customFeatures?","") === "1";
    }catch(e){

    }
    return false;
}
window.hasCustomFeatures=hasCustomFeatures;

function onEulaError(){
    alert("Failed to load the eula!");

}
function onEulaLoaded(){
    if(!window.ko){
        if(BundleData == null) return;
        var bundle=BundleData[CurrentBundle];
        renderFeatures(bundle);
        //TODO: Handle OptIn Eula
        renderOptin(bundle);
        fitIframe(bundle);
        $("#frameEula").show(); 
    }else{
        window.model.eulaLoaded(true);
    }
    issueCommand("window/innerloaded",$("#frameEula").attr("src"));
    
}


//Size features to make sure iframe works.
function fitIframe(){
    var footerPx=footerHeight;
    var fbar=$("#feature-bar");
    if(fbar.is(":visible")) footerPx=footerPx+fbar.outerHeight();
    $(".eula").css("bottom", footerPx  + "px");
    $(".eula").css("height","auto");
}

function addFeature(bundle,feat,name,text,checked){
    var fbar=$("#feature-bar");
    var template=$(".template",fbar);

    var clone=template.clone();
    if(bundle.CustomCss && bundle.CustomCss._body_){
        clone.attr("style",bundle.CustomCss._body_);
    }
    text=text||feat._a_.Name;
    var span=$("span",clone).text(text);
    var input= $("input",clone)
    span.bind('click',input,function(e){
        if(!e.data.is(":checked")) e.data.attr("checked","true");
        else e.data.removeAttr("checked");
    },input);
    input.val(text||feat._a_.Name)
    if((checked||feat._a_.InitialState)=="checked"){
        input.attr("checked");
    }else{
        input.removeAttr("checked");
    }
    input.attr("id",name);
    clone.removeClass("template").addClass("feature").appendTo(fbar);
}

//Do we have optin
function hasOptin(){
    return AppData.OptInStyle && AppData.OptInStyle._body_ === "true"
}

//Add and optin element
function renderOptin(bundle){
    try{
        if(hasOptin()){
            var checked=(bundle._willInstall_==1)
            if(bundle._willInstall_ === undefined){
                checked=bundle.OptInDefault._body_ === "true"?true:false;
            }
            addFeature(bundle,undefined,"chkOptin",bundle.OptInText._body_,
            checked?"checked":"unchecked");
            var fbar=$("#feature-bar");
            fbar.show();

        }
    }catch(e){
    }
}

//Add the Feature Elements
function renderFeatures(bundle){
    var fbar=$("#feature-bar");
    var template=$(".template",fbar);
    $(".feature",fbar).remove();
    var x=null;
    if(bundle.Feature.length  == 0){    
        fbar.hide();
        return;
    }
    /**
    * Check to see if we have embedded Features in the Eula
    */
    if(hasCustomFeatures()){
        fbar.hide();
        return;
    }

    for(x in bundle.Feature){
        var feat=bundle.Feature[x];
        //If this feature is a directive we will not add it .
        if(feat.isDirective || feat.isHidden) continue;
        addFeature(bundle,feat,"Feature_" + x);
    }
    fbar.show();

}




//Go to the Next Bundle.
function nextBundle(accepted,tgtBundle){
    var _CurrentBundle=tgtBundle || CurrentBundle;
    var bundle=BundleData[_CurrentBundle];

    if(bundle!=null){ // For Bundles that were skipped we wont pass the information over.
        var featureFlags=[]
        //If the features are handled from within the eula then 
        //we will not collect them from this frame.
        //clicks will be tracked by onFeatureChange.
        if(!hasCustomFeatures()){ //Then transfer over the feature state.
            for(var x in bundle.Feature){
                var elt=$("#Feature_" + x);
                //Make sure we only update features we control
                if(elt.length>0){
                    var checked=elt.is(":checked");
                    var newState=bundle.Feature[x]._a_.InitialState=checked?"checked":"unchecked";
                    if(checked) featureFlags.push(bundle.Feature[x]._a_.Options);
                    issueCommand("bundle/featureState",[bundle.bundleIndex-1,x,newState].join("|"));
                }
            }
        }else{
            //Have custom features so we need to reload the features array from 
            //the Lua side before wbe put the flags together.
            bundle.Feature=eval(issueCommand("bundle/features",bundle.bundleIndex-1))
        }


        //Sync the bundle state on the Lua Side.
        if(bundle.isConsolidated){
            //Consolidated bundles state is controlled by something else
            debug_log("Bundle[" + _CurrentBundle + "] is consolidated"); 
        }else{

            //This is an arrya of objects
            bundle._willInstall_=accepted?1:0;
            var ret=issueCommand("bundle/setProdState",[_CurrentBundle,bundle._willInstall_,
                    (bundle._willInstall_==1?"accept":(bundle._willDisplay_ ==1 ?"decline":"hidden"))].join("|"));
            try{
                var resp=eval(ret); 
                for(var i=0;i< resp.length;++i){
                    var b=BundleData[i],newval=resp[i];
                    b._willInstall_ = newval._willInstall_;
                    b._willDisplay_ = newval._willDisplay_

                }
            }catch(e){
            }
            try{
                var frame=$("#frameEula"),
                callback=(bundle._willInstall_?"onAccept":"onDecline"),
                toCall=["frameEula",bundle.ProductEula._body_,"window." + callback + " && window." + callback + "()" ].join("\x01");

                issueCommand("app/frameEval",toCall);
            }catch(_){
            }

        }

        /*
         Due to the Abnormal Window messaging issue.s
         I cannot safely compiute featureOptions here.
         This is because the actual feature confirmation  actions 
         that are run from the eula iframe get evaluated after the next page loads.
         This is okay becayse the order is still preserved.
         for(var x in bundle.Feature){
         var f=bundle.Feature[x];
         if(f._a_.InitialState == "checked") 
         featureFlags.push(f._a_.Options);
    }

    issueCommand("bundle/featureOptions",[CurrentBundle,featureFlags.join(" ")].join("\x01"))*/
    }
    //bundle.state=accepted?"accept"
    if(_CurrentBundle+1 == BundleData.length){
        //Update the Lua Side State.
        issueCommand("nav/install");
    }else{
        //Move to the Next Offer
        offerBundle(_CurrentBundle+1,1,true);
    }
}
function prevBundle(tgtBundle){
    _CurrentBundle=tgtBundle|| CurrentBundle
    if(_CurrentBundle ==FirstBundle) return;
    offerBundle(_CurrentBundle-1,-1);
}

function navAcceptClick(){
    if(isUninstaller()){
        return
    }
    var cmd=$("#accept-button").attr("navCommand");
    navButtonClick(cmd);
}

function stopBubble(e){
    if(!e) return;
    e.cancelBubble=true;
    e.returnValue=false;
}

//handle a skip all click
function doSkipAll(allOffers){
    var bundle=BundleData[CurrentBundle];
    //Dont check CurrentBundle because 
    //it is not true that the primary product will be bundle IDX=0
    if(bundle){
        if(bundle.isPrimary){
            issueCommand("bundle/setProdState",[CurrentBundle,1, "accept","skipall"].join("|"));
        }
    }
    issueCommand("nav/skipall",allOffers?"true":"false"); 
}

//Navigation button handlers
function navButtonClick(which,e){
    e=e||window.event;
    if(e) stopBubble(e);
    if(which == "accept"){
        if(hasKo){
            
            //We are using knockout so this stuf
            //
            nextBundle(model.isPrimary() || model.installThisOne() == "yes"); 
        }else{
            if(hasOptin()){
                if(CurrentBundle === 0 && !$("#chkOptin").is(":checked")){
                    var msg=issueCommand("lookup/message",CurrentBundle + "\x01UI.OPTIONACCEPT");
                    if(!msg|| msg == "") msg= "Please accept the terms to continue." ;
                    //alert(msg);
                    return 
                }
                nextBundle($("#chkOptin").is(":checked"));
            }else{
                //Check if the would install flag is set.
                var bundle=BundleData[CurrentBundle];
                //IN the absense of would install we accept.
                if(typeof bundle._wouldInstall_   === 'undefined'){
                    nextBundle(true);
                }else {
                    if(bundle._wouldInstall_ == -1){
                        nextBundle(true);
                    }else{
                        //If there is a would install flag then we honor it 
                        nextBundle(bundle._wouldInstall_ == 1);
                    }
                }
            }
        }
    }else if(which == "decline"){
        nextBundle(false);
    }else if(which == "back"){
        prevBundle();
    }else{
        issueCommand("nav/" + which);
    }
}

function windowButtonClick(which,e){
    var e=e||window.event;
    if(e) stopBubble(e);
    issueCommand("window/" + which);
    //alert(which);
}

//Issue a command to the Parent
function issueCommand(name,data,callback){
    try{
        return window.external.issueCommand(name,data);
    }catch(e){
    }
}




function setupDocumentEvents(){
    $(document).keydown(function(e){
        var code = (e.keyCode ? e.keyCode : e.which);
        //alert("KEY PRESSED:" + code);
        if(code == 13) { //Enter keycode
        e.preventDefault(); //Docuyment keydown is prevented all the time
            if(BundleData){
                var bundle=BundleData[CurrentBundle];
                if(requiresClick(bundle)){
                    return ;
                }
            }
            var $tgt=$(e.target);
            //If the target had an onclick then let it be
            if($tgt.attr("onclick")){
                $tgt.click();
                return;
            }
            if(  $tgt.attr("href")){
                return;
            }
            $("#accept-button").click();
            //Do something
        }
    });
    $("#accept-button").keydown(function(e){
        var code = (e.keyCode ? e.keyCode : e.which);
        //alert("KEY PRESSED:" + code);
        if(code == 13) { //Enter keycode
            if(BundleData){
                var bundle=BundleData[CurrentBundle];
                if(requiresClick(bundle)){
                    e.preventDefault();
                    //Prevent all other even handlers from firing
                    e.stopImmediatePropagation();
                    return ;
                }
            }
        }

    });
}

function setupDragHandler(){
    $("body").mousedown(function(e){
        var target=$(e.target);
        //Some elements cant initiate a drag
        if(target.attr("href")) return;//Links dont start drags
        if(target.closest(".nodrag").length >0 ) return;
        if(e.which ==1){
            issueCommand("window/begindrag");
        }
    });
}

//Get the status of a download
var getStatus=function(bundle){
    if(bundle._installed_ == 1) return "Installed";
    return "Waiting";
}

var progressCaption=function(bundle){
    return bundle.ProductName._body_
}

function setProgressCaptionFunction(func){
    progressCaption=func;
}

function renderBeginInstall(){
    updateBodyClass("install");
    var tmpl=$("#divInstallItem").html();
    $("#divInstallItem").hide();
    var html="";
    var primaryHtml="";//HTML for primary products
    var installInOrder = issueCommand("app/InstallInOrder?") == "true",
    singleProgressBar =  hasSingleProgressBar(),
    rowIdx=0,rows=BundleData.length;
    if(singleProgressBar){
        rows=1;
    }

    for(var j=0;j<rows;++j){
        var i=j;
        var bundle=BundleData[i];
        if(!singleProgressBar){
            if(bundle._willInstall_ != 1) continue;
            if(bundle.noProgress ) continue;
        }else{
            i=0;
        }
        var status=getStatus(bundle);
        var params=INSTALL_DATA[status];
        var body= tmpl.replace("{ProductName}",progressCaption(bundle))
        .replace("{ProductStatus}",params[0]);
        var block="<div id='divInstall" + (1+i) + "' class='install-item' >" + body + "</div>";
        if(bundle.isPrimary && !installInOrder ){
            primaryHtml=primaryHtml+block;
        }else{
            html=html+block; 
        }
    }
    $("#divInstallItems").html(html + primaryHtml);
    //Handle striping again
    var rowIdx=0;
    $("#divInstallItems").find(".install-item").each(function(){
        var evenorodd=rowIdx%2==0?"even":"odd";
        $(this).addClass(evenorodd);
        rowIdx++;
    });
    $("#divInstallPane").show();
    $("#spnCaption").text("Installing Products");
    //Hide accept decline and back.
    $("#accept-button,#decline-button,#back-button").hide();
    //Hide the list of apps to be installed
    $("#ulAccepted,#divAccepted,.offer-screen-only").hide();

    //Hide the ffeature bar
    var fbar=$("#feature-bar").hide();
    $(".feature",fbar).remove();
    $("#footer-steps .page-container").hide();
    for(var i=0;i<BundleData.length;++i){
        var bundle=BundleData[i];
        if(bundle._willInstall_!=1) continue;
        var status=getStatus(bundle);
        var params=INSTALL_DATA[status];
        var item=$("divInstall" +(i+1));
        updateInstallClass($(".item-status",item),params[1]);
        updateInstallLine(i+1,status);
    }

}

//Begin an Installation.
function beginInstall(){
    if(!window.ko){
        renderBeginInstall();
    }else{
       model.state(STATE_INSTALLING);
    }
    setupCustomFeatures(); //This will hide the features and such.
}

function launchUrl(url){
    try{
        issueCommand("open/url",url);
    }catch(_){
    }
}
function openExternalUrl(){
    var e = (arguments.length ==1)?arguments[0]:arguments[1];
    
    var $this=$(e.target),
    href=$this.attr("href");
    //PRevent Default and then launch the url
    e.preventDefault();
    launchUrl(href);
}
/**
 * Urls that open out of the installer are marked.
 */
function setupLaunchUrl(){
    $("body a.external-url[href]").click(openExternalUrl);

}

//Delayed Refresh of theui
function delayedRefresh(){
    window.setTimeout(function(){
        issueCommand("window/refresh","");
    },20); 
}

function updateBodyClass(clazz){
    $("body").removeClass("offer install cancel complete").addClass(clazz);
}

function renderBeginCancel(){
    updateBodyClass("cancel");
    var html="";
    for(var i=0;i<BundleData.length;++i){
        var bundle=BundleData[i];
        if(bundle == null) continue;
        if(bundle._willInstall_!=1) continue;
        html=html+"<li>" + bundle.ProductName._body_+ "</li>"; 
    }
    $("#ulCancel").html(html);
    $("#spnCaption").text("Installation Incomplete");
    //Hide decline and back.
    //THis is misleading but "nav/install is really clicing the accept button"
    $("#cancel-button").click(function(){navButtonClick("cancel"); }).val("Quit");
    $("#accept-button").val("Accept").attr("navCommand","install");
    $("#decline-button,#back-button").hide();
    $("#divCancelPane").show();
    $("#ulAccepted").hide();
    $("#divAccepted").hide();
    $("#footer-steps .page-container").hide();
    var fbar=$("#feature-bar").hide();
    $(".feature",fbar).remove();


}

//Begin a cancellation
function beginCancel(){
    if(!window.ko){
        renderBeginCancel();
    }else {
        model.state(STATE_CANCEL);
    }
    setupCustomFeatures();
    delayedRefresh();
}


function renderBeginComplete(){
    $("#decline-button,#back-button").hide();
    var cancel= $("#cancel-button").click(function(){navButtonClick("install-later"); }).attr("onclick",null);
    var accept=$("#accept-button").attr("navCommand","install-now").attr("onclick",null);
    cancel.find("a").text("Install Later");
    accept.find("a").text("Install Now");
    $("#spnCaption").text("Installation Complete");
    $("#footer-steps .page-container").hide();
    $("#ulAccepted,#divAccepted,#divCancelPane,#ulCancel").hide();
}

/**
 * Begin the Complete Process.
 */
function beginComplete(){
    if(!window.ko){
        renderBeginComplete()
    }else{
        model.state(STATE_COMPLETE);
    }
    delayedRefresh();
}

/**
 * String Name,CSS CLASS, oscillating, technically fully downloaded?
 */
var INSTALL_DATA= {
    Installed:["INSTALLED","installed",0 ,true],
    "Download Error":["FAILED","download-error",0,true ],
    "Downloading":["Downloading...","downloading",0,false],
    "Installing":["Installing...","installing",1,true],
    "Waiting":["Waiting...","waiting",0,false]
};
INSTALL_DATA["Downloaded"]=INSTALL_DATA["Downloading"];
INSTALL_DATA["Download Failed"]=INSTALL_DATA["Download Error"];
/**
* Given and instal item cell remove all the other classes and add a new one
*/
function updateInstallClass(elt,newclass){
    for(var x in INSTALL_DATA){
        var clazz=INSTALL_DATA[x][1];
        elt.removeClass(clazz);
    }
    elt.addClass(newclass);
    return elt;
}

//INvoked from NSIS to update a row.
function updateInstallLine(idx,status,originalIdx){
    var params=INSTALL_DATA[status];
    if(hasKo){
        window.model.updateInstallLine(idx,status,originalIdx);
        return;
    }
    var bundle=BundleData[originalIdx-1]
    if(bundle == null) return;
    if(hasSingleProgressBar()){
        if(params[3] == true){
            //Mark the bundle as installed
            bundle._fullydownloaded_=true;
        }
        idx=1;
    }
    var item=$("#divInstall" + idx);
    updateInstallClass($( " .item-status",item ).text(params[0]),params[1]);
    try{
        $(".item-name",item).text(progressCaption(bundle) );
    }catch(_){
    }

    setupOscillating(idx,params[2] ==1?true:false);
    if(status=="Installed") {
        $(".install-progress-inner",item).css("width","100%");
    }
    //$(".install-progress-bar",item)[params[2]==1?"addClass":"removeClass"]("oscillating");
}


function setupOscillatorTimer(){
    if(isUninstaller()) return;
    setInterval(updateOscillators,100);
}

//Callback Function to update oscilating Progress entries.
function updateOscillators(){
    $(".install-progress-bar.oscillating .install-progress-inner").each(function(){
        var elt=$(this);
        var current=$(this).attr("osc_pos") || 0;
        current=current*1;//convert to integer
        var len=$(this).parent().innerWidth()-50;
        // 0->len == positive, len ->2*len == negative;
        current=current +10;
        var pos= current % (len*2);
        if(pos >len){
            pos =(2*len) -pos;
        }
        $(this).css("left",pos + "px");
        $(this).attr("osc_pos",current);

    });
}

/**
*  Setup Oscillating Progress
*/
function setupOscillating(idx,osc){

    var elt=$("#divInstall" + idx);
    if(osc){
        $(".install-progress-bar",elt).addClass("oscillating");
        $(".install-progress-inner",elt).css("width","50px");
    }else{
        $(".install-progress-bar",elt).removeClass("oscillating")
        $(".install-progress-inner",elt).css("width","0px");
        $(".install-progress-inner",elt).css("left","0px");
    }

}

function singleProgressCalc(idx,min,max,stepIdx){
    var ret={min:min,max:max};
    try{
        var steps=AppData.TotalSteps || 0;
        //If there is a total download lets get it.
        if(AppData.TotalDownloadSize){
            ret.max=AppData.TotalDownloadSize;
            //We need to compute Min by adding min to the mins of the prior products.
            ret.min=0
            for(var i=0;i<BundleData.length;++i){
                var b=BundleData[i];
                if(b ==null) continue;
                if(i == (idx-1)){
                    ret.min=ret.min+min;
                }else if(b._installed_ == 1 || b._fullydownloaded_ ){
                    ret.min = ret.min + (b.TotalBundleBytes || 0);
                }
            }
        }
        if(steps > 0  && !AppData.TotalDownloadSize){
            var pcntPerStep=100/steps;
            ret.max=100; //Force max to 0-100 scale'
            //Calculate min as percent of steps + percent of substep
            ret.min=(pcntPerStep * (steps -1)) + ((min/max) * pcntPerStep);
        }
    }catch(_){
        issueCommand("debug/log",_ + "|" + _.message);
    }
    return ret;
}


//update installation progress
function updateInstallProgress(idx,min,max,stepIdx,canPause){
    try{
        if(hasKo){
            window.model.updateProgress(idx,min,max,stepIdx,canPause);
        }else{
            if(hasSingleProgressBar()){
                var progCalc=singleProgressCalc(idx,min,max,stepIdx);
                min=progCalc.min;
                max=progCalc.max;
                idx=1;
            }
            var elt=$("#divInstall" + idx);
            var percent=(Math.min(1,Math.max(0,((min/max))))*100).toFixed(2) + "%";

            if(max == 0 || max  == ""){
                //$(".item-progress",elt).text(toMB(min)  + "MBs");
            }else{
                $(".install-progress-inner",elt).css("width",percent);
            }
        }
    }catch(e){
        issueCommand("debug/log",e + "|" + e.message );
    }
}

function toMB(val){
    return (val /(1024*1024) ).toFixed(1);
}

function toHuman(val){
    try{
        if(isNaN(val)) return "0.0K";
    var MEGABYTE= 1024*1024;
    if(val < MEGABYTE) return (val / 1024).toFixed(1) + "K"
    return (val/MEGABYTE).toFixed(1) + "MB"
    }catch(_){
        return "???";
    }
}
/**
* Enable the Debug Mode.
*/
function enableDebug(){
    DEBUG_MODE=true;
    $("body").keypress(function(e){
        if(e.which == "r".charCodeAt(0)){
            delayedRefresh(); 
        }
    });
    if(window.ko){
        var watchField=function(name){
            return function(x){
                if(typeof(x) == "object"){
                    x=$.param(x)
                }
                issueCommand("debug/log","StateVar[" + name + "] -> " + x);
            }
        }
        if(window.model){
            $.each( ["state","isLeadProduct","isOffer","productEulaUrl","ui"],function(){
                window.model[this].subscribe(watchField(this));
            })
        }
    }
}

function hasSingleProgressBar(){
    return issueCommand("app/SingleProgressBar?") == "true";
}

function hasVariation(name){
    return issueCommand("app/hasVariation?",name) == "true";
}

var hasSkipAll=function(){
    return  hasVariation("skip-all");
}

/**
 * Show Skip All - 
 * mode =>  Primary|FirstAdvertiser|AllAdvertisers|AllOffers
 */
var showSkipAll=function(position,currentBundle){
    switch(position){
    case "Primary":
        return currentBundle.isPrimary
    case "FirstAdvertiser":
        return currentBundle.advertiserIndex == 1
    case "AllAdvertisers":
        return !currentBundle.isPrimary;
    case "AllOffers":
        return true
    }
    return false;
}

function log(x){
    issueCommand("debug/log",x.toString());
}

function setCancelMessage(msg){
    issueCommand("cancel/message",msg)
}


//UNINSTALL CODE!!!

/**
 * Handle Running Uninstall process.
 */
function loadKnockout(callback){
    if(!window.ko){
        var script=document.createElement('script');
        script.src="res/knockout.js";
        var head=document.getElementsByTagName('head')[0],
        done=false;
        script.onload=script.onreadystatechange = function(){
            if ( !done && (!this.readyState
                    || this.readyState == 'loaded'
                    || this.readyState == 'complete') ) {
                try{
                    done=true;
                    script.onload = script.onreadystatechange = null;
                    loadKoModel();
                    hasKo=true;
                    head.removeChild(script);
                    callback()
                }catch(e){
                    console_log(e,true);
                }
                    }
        };
        head.appendChild(script);
    }else callback()
}

var UninstallRecord=function(data,bundle){
    this.data=data;
    this.bundle=bundle;
    this.uninstall=ko.observable(false);
    this.state = ko.observable(0);
}
$.extend(UninstallRecord.prototype,{
        name:function(){
            try {
                return  this.data.display_name || this.bundle.ProductName._body_;
            }catch(_){
                return "";
            }
        },
        id:function(){
            return this.data.id;
        },
        stateString: function(){
            switch(this.state()){
            case -1: return "Not Found"
            case 0: if (!this.uninstall() ) return "Unchanged"
                return "Waiting"

            case 1: return "Uninstalling ..." 
            case 2: return "Uninstalled ..."
            default:
                return "-"
            }

        }
});


var startUninstall=ExceptionWrap(function(){
    issueCommand("app/data");
    //Move to Uninstall State
    uninstAttribs=window.model.AppData().Uninstaller && window.model.AppData().Uninstaller._a_;

    window.model.applicationTitle= ko.computed(function(){
        return (uninstAttribs && uninstAttribs.name) ||  (this.productName() +  " Uninstaller");
    },window.model);
    window.model.Uninstallers=ko.computed({read:function(){
            var bundles=this.BundleData();
            return ko.observableArray($.map(this.AppData().uninstallers || [],function(v,k){
                return new UninstallRecord(v,bundles[v.bundleIndex-1]);
            }));
    },owner:window.model,deferEvaluation:true});
    $.extend(window.InstallModel.prototype,{
            launchUninstaller:function(record){
                //TODO :Implement
                issueCommand("nav/uninstall",record.data.id);
            },
            completeUninstaller:function(){
                //To begin the uninstall
                //Uninstall is complete.
                issueCommand("nav/uninstall-complete");
                return 
            },
            hasProducts:function(){
                return this.Uninstallers()().length > 0;
            },findUninstallRecord:function(id){
                var res=$.grep(this.Uninstallers()(),function(v,idx){
                    return id==v.id();
                });
                return  (res.length  > 0) ?res[0]:null;
            },removeUninstaller: function(id){
                //Remove all the uninstallers matching that id
                ////Remove all the uninstallers matching that id
                this.Uninstallers().remove(function(item){
                    return item.id() == id;
                });
            }
   })
    window.model.uninstallSteps=[1,2,3];
    window.model.uninstallStep=ko.observable(1);
    window.model.uninstallTotalSteps=3;
    window.model.state(STATE_UNINSTALL);
    ko.cleanNode(document)
    ko.applyBindings(window.model);
})

function isUninstaller(){
    return issueCommand("app/isUninstaller?",name) == "true";
}

function pickInstallFolder(title,action){
    action=action|| ""
    return issueCommand("app/pickfolder",[title,action].join("\x01"));
}
var startingUninstalls=function(){
    window.model.uninstallStep(2)
}

var uninstallFailed=ExceptionWrap(function(id){
    var record=window.model.findUninstallRecord(id);
});

var uninstallClosed=ExceptionWrap(function(id){
    var record=window.model.findUninstallRecord(id);
    if(record) record.state(0);
});
var uninstallComplete=ExceptionWrap(function(id){
    var record=window.model.findUninstallRecord(id);
    if(record){
        record.state(2);
        //REmove the uninstaller that just completed
        window.model.removeUninstaller(id);
    }
});
var uninstallStarting=ExceptionWrap(function(id){
    var record=window.model.findUninstallRecord(id);
    if(record) record.state(1);
});

var uninstallFinish=function(){
    window.model.uninstallStep(3);
}


/*================================================*/


$(setupDragHandler);
$(setupLaunchUrl);


$(setupOscillatorTimer);
$(setupDocumentEvents);

//Load Knockout if available 
if(hasKo){
    loadKoModel();
}
