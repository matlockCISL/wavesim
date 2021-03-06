%%% Simulates the wave propagation of a point source in a 2D random medium
%%% Gerwin Osnabrugge 2015

clear all; close all;
addpath('..');

%% options for grid (gopt) and for simulation (sopt) 
PPW=4; %points per wavelength = lambda/h
sopt.lambda = 1; %in mu %lambda_0 = 1; %wavelength in vacuum (in um)
sopt.energy_threshold = 1E-16;
sopt.callback_interval = 1000;
sopt.max_iterations = 6000;

mopt.lambda = sopt.lambda;
mopt.pixel_size = sopt.lambda/PPW;
mopt.boundary_widths = [0, 0]; %periodic boundaries
mopt.boundary_strength = 0;
mopt.boundary_type = 'PML3';
N = [64*PPW 64*PPW]; % size of medium (in pixels)

%% Construct random medium
% real refractive index
n0 = 1.3;        % mean
n_var = 0.1;     % variance

% imaginary refractive index
a0 = 0.05;       % mean
a_var = 0.02;    % variance

% randomly generate complex refractive index map
n_sample = 1.0*(n0 + n_var * randn(N)) + 1.0i*(a0 + a_var * randn(N));

% low pass filter to remove sharp edges
n_fft = fft2(n_sample);
window = [zeros(1,N(2)/4), ones(1,N(2)/2), zeros(1,N(2)/4)]' * [zeros(1,N(1)/4), ones(1,N(1)/2), zeros(1,N(1)/4)];
n_sample = ifft2(n_fft.*fftshift(window));

% construct sample object
sample = SampleMedium(n_sample, mopt); 

%% define a point source at the medium center
source = sparse(N(1), N(2));
source(end/2,end/2) = 1; % point source

%% wavesim simulation
sim = wavesim(sample, sopt);
E = exec(sim, source);

%% plot resulting field amplitude
figure(1); clf;

%set axes
x = (-N(2)/2 + 1 : N(2)/2) /PPW;
y = (-N(1)/2 + 1 : N(1)/2) /PPW;

% plot refractive index distribution
subplot(1,2,1);
imagesc(x,y,real(n_sample));
axis square;
xlabel('x / \lambda','FontSize',16);
ylabel('y / \lambda','FontSize',16);
h = colorbar;
set(get(h,'Title'),'String','n','FontSize',18,'FontName','Times New Roman');
set(gca,'FontSize',14);

% plot resulting field amplitude
subplot(1,2,2);
imagesc(x,y,log(abs(E)));
axis square;
xlabel('x (\lambda)','FontSize',16);
ylabel('y (\lambda)','FontSize',16);
h = colorbar;
set(get(h,'Title'),'String','log|E|','FontSize',18,'FontName','Times New Roman');
set(gca,'FontSize',14);

