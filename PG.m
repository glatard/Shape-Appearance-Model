function PG(dat,s)
% Combined principal geodesic analysis and generalized(ish) PCA
% FORMAT PG(dat,s)
% dat - a data structure containing filenames etc
% s   - various settings
%__________________________________________________________________________
% Copyright (C) 2017 Wellcome Trust Centre for Neuroimaging

% John Ashburner
% $Id$

spm_field('boundary',0);
spm_diffeo('boundary',0);
if ~exist('s','var'), error('No settings'); end

if ~isfield(s,'continue') || s.continue==false,
    PGdistribute('init',s);
    PGdistribute('share',dat);

    % Start from scratch
    [s0,s1,s2] = PGdistribute('SuffStats',s);
    [mu,noise] = ComputeMean(s0,s1,s2,s);
    d          = [size(mu) 1 1];
    mat        = eye(4);
    [mu_fa,Wa,Wv,WWa,WWv,WW] = CreateBases(s,mu,mat);
    K          = size(WW,1);

    PGdistribute('RandomZ',K);
    [ss.N,ss.Z,ss.ZZ,ss.sS] = PGdistribute('GetZZ');
    PGdistribute('AddToZ',-ss.Z/ss.N);
    ss.ZZ     = ss.ZZ - ss.Z*ss.Z'/ss.N;
    ss.Z      = ss.Z*0;
    [U,S]     = svd(ss.ZZ);
    Rz        = 0.1*sqrt(ss.N/K)*U/sqrtm(S);
    ss.ZZ     = Rz'*ss.ZZ*Rz;
    ss.sS     = Rz'*ss.sS*Rz;
    PGdistribute('TransfZ',Rz);
    [ss.N,ss.Z,ss.ZZ,ss.sS] = PGdistribute('GetZZ');

    s.omega   = 1;
else
    % Continue from previous results
    new_s = s;
    load(fullfile(s.result_dir,['train' s.result_name '.mat']),...
        'Wa','Wv','WWa','WWv','dat','ss','EA','B','mu','s','noise','dat');
    %old_s = s;
    s     = new_s;
    % Should really include some checks here
    PGdistribute('init',s);
    %PGdistribute('share',dat);
    [ss.N,ss.Z,ss.ZZ,ss.sS] = PGdistribute('GetZZ');
end

[EA,B,lb_qA,lb_pA] = SetReg(ss.ZZ+ss.sS,ss.N,s);
lb_A               = s.wt(1)*(lb_pA  - lb_qA);

maxit = 30;
if isfield(s,'maxit'), maxit = s.maxit; end

ls1 = 1;
if isfield(s,'ls1'), ls1 = s.ls1; end

wt       = s.wt;
itscales = logspace(log10(ls1),log10(1),maxit);

for iter = 1:maxit,
    fprintf('%-3d    ', iter);

    [Wa,Wv,WWa,WWv,WW,s.omega] = Mstep(mu,Wa,Wv,noise,B,ss.ZZ,EA,WWa,WWv,s);
    
    lb_pW    = -0.5*trace(B*WW); % + const
    RegZ     = double(s.wt(1)*EA + s.wt(2)*WW);
    ss       = PGdistribute('UpdateZ',mu,Wa,Wv,noise,RegZ,s);
    lb_L     = ss.L;
    lb_L     = lb_L + 0.5*ss.N*(s.wt(1)*LogDet(EA) - LogDet(RegZ));

    PGdistribute('AddToZ',-ss.Z/ss.N); % Should really compute a different mean here
    ss.ZZ = ss.ZZ - ss.Z*ss.Z'/ss.N;

    [noise,lb_lam] = NoiseModel(ss,s,d);
    [mu,lb_pmu]    = MuUpdate(mu,ss.gmu,ss.Hmu,ss.N,s);
    if isfield(s,'ondisk') && s.ondisk
        mu_fa(:) = mu(:);
    end

   %subplot(2,2,1); image(ColourPic(mu,s.likelihood)); axis image ij off;
   %subplot(2,2,2); imagesc(abs(ss.ZZ)/ss.N);  colorbar; axis image; title ZZ
   %subplot(2,2,3); imagesc(abs(WW));  colorbar; axis image; title WW
   %subplot(2,2,4); imagesc(abs(WWv)); colorbar; axis image; title WWv
   %drawnow

    switch lower(s.likelihood)
    case {'normal','laplace'}
        lb = lb_L + lb_pW + lb_pmu + lb_A + lb_lam;
        fprintf(' %8.6g %8.6g %8.6g %8.6g %8.6g     %8.6g   %g ', ...
             lb_L,  lb_pW,  lb_pmu,  lb_A,  lb_lam,  lb, s.omega);
    case {'binomial','multinomial'}
        lb = lb_L + lb_pW + lb_pmu + lb_A;
        fprintf(' %8.6g %8.6g %8.6g %8.6g    %g  %g ', ...
            lb_L,  lb_pW,  lb_pmu,  lb_A, lb, s.omega);
    case {'other'}
    otherwise
        error('Unknown likelihood function.');
    end

    s.wt(2) = wt(2)*itscales(iter);
    WWa     = UpdateWWa(Wa,s);
    WWv     = UpdateWWv(Wv,s);
    [Wa,Wv,WWa,WWv,ss,WW] = OrthAll(Wa,Wv,WWa,WWv,ss,s);
    [EA,B,lb_qA,lb_pA]    = SetReg(ss.ZZ+ss.sS,ss.N,s);

    lb_A   = s.wt(1)*(lb_pA  - lb_qA);
    RegZ   = double(s.wt(1)*EA + s.wt(2)*WW);

    dat    = PGdistribute('Collect');
    save(fullfile(s.result_dir,['train' s.result_name '.mat']),...
        'Wa','Wv','WWa','WWv','dat','ss','EA','B','RegZ','mu','s','noise','dat');

    %subplot(2,2,1); image(ColourPic(mu,s.likelihood)); axis image ij off;
    %subplot(2,2,2); imagesc(abs(ss.ZZ)/ss.N);  colorbar; axis image; title ZZ
    %subplot(2,2,3); imagesc(abs(WW));  colorbar; axis image; title WW
    %subplot(2,2,4); imagesc(abs(WWv)); colorbar; axis image; title WWv
    %drawnow

    fprintf('\n');
    %if s.omega<0.001, break; end
end

