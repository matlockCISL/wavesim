classdef SampleMedium
% SampleMedium - Generates a sample object for use in wave
% simulations (wavesim, PSTD)
% Ivo Vellekoop 2017
    properties
        e_r % relative dielectric constand map with boundaries appended
        e_r_max % maximum real part of obj.e_r
        e_r_min % minimum real part of obj.e_r
        e_r_center % (e_r_max+e_r_min)/2
        roi % size of the original refractive index map without padding
        grid %  simgrid object, with x and k ranges
        leakage = 0
        dimensions % number of dimensions (2 or 3). Internally we use 3-D arrays for everything
    end
    methods
        function obj = SampleMedium(refractive_index, options)
            % SampleMedium - Generates a sample object for use in wave
            % simulations (wavesim, PSTD, FDTD)
            % 
            % internally, the object stores a map of the relative dielectric
            % constant (e_r), which is the refractive index squared. The e_r map
            % is padded with absorbing boundaries, and then expanded to the next
            % multiple of 2^N in each dimension (for fast fourier transform)
            %
            % refractive_index   = refractive index map, may be complex, need not
            %                      be square. Can be 2-D or 3-D.
            % options.pixel_size = size of a grid pixel in any desired unit (e.g.
            % microns)
            % options.lambda     = wavelength (in same units as pixel_size)
            % options.boundary_widths = vector with widths of the absorbing
            %                          boundary (in pixels) for each dimension. Set element
            %                          to 0 for periodic boundary.
            % options.boundary_strength = maximum value of imaginary part of e_r
            %                             in the boundary (for 'PML' only)
            % options.boundary_type = boundary type. Currently supports 'window' (default) and
            % 'PML1-5'
            % options.ar_width = width of anti-reflection layer (for
            % 'window' only). Should be < boundary_widths. When omitted, a
            % default fraction of the boundary width will be used
            % (pre-factor may change in the future)
            %
            %% Set default values and check validity of inputs
            assert(numel(options.boundary_widths) == ndims(refractive_index));
            if ~isfield(options, 'ar_width')
                options.ar_width = round(options.boundary_widths/2); %this factor may change into a more optimal one!!!
            end
            
            % For simplicity, we use 3-D arrays internally for everything.
            % if the refractive index array is 2-D, convert it to 3-D
            % the extra dimension is added as the first dimension because
            % Matlab does not support trailing singleton dimensions for 3-D
            % arrays
            if ismatrix(refractive_index)
                obj.dimensions = 2;
                options.boundary_widths = [0, options.boundary_widths];
                refractive_index = reshape(refractive_index, [1, size(refractive_index)]);
                if ismatrix(refractive_index) % still a matrix, this could happen because the original map was Nx1 ==> 1xNx1 ==> 1xN
                    error('1-D simulations are not supported, use a refractive index map that is at least 2x2');
                end
            else
                obj.dimensions = 3;
            end


            %% calculate e_r and min/max values
            obj.e_r = refractive_index.^2;
            obj.e_r_min = min(real(obj.e_r(:)));
            obj.e_r_max = max(real(obj.e_r(:)));
            obj.e_r_center = (obj.e_r_min + obj.e_r_max)/2;

            % construct coordinate set. 
            % padds to next efficient size for fft in each dimension, and makes sure to
            % append at least 'boundary_widths' pixels on both sides.
            obj.grid = simgrid(size(obj.e_r) + options.boundary_widths, options.pixel_size);
            
            %% Currently, the simulation will always be padded to the next efficient size for a fft
            % This is ok if we have boundaries, but if we have periodic boundary
            % conditions, the field size must not change.
            % so, here we check if the size is unchainged if we specify boundary_width == 0.
            if any(options.boundary_widths==0 & obj.grid.padding > 0)
                error('If periodic boundary conditions are used, the sample size should be a power of 2 in that direction');
            end

            % applies the padding, extrapolating the refractive index map to
            % into the added regions
            [obj.e_r, obj.roi, Bl, Br] = SampleMedium.extrapolate(obj.e_r, obj.grid.N);
            [obj.e_r, obj.leakage] = SampleMedium.add_absorbing_boundaries(obj.e_r, Bl, Br, options); 
        end
    end
    methods (Static)
        function [e_r_full, roi, Bl, Br] = extrapolate(e_r, new_size)
            %% Expands the permittivity map to 'new_size'
            % The new pixels will be filled with repeated edge pixels
            
            % Calculate effective boundary width (absorbing boundaries + padding)
            % on left and right hand side, respectively.
            roi_size = size(e_r);
            Bl = ceil((new_size - roi_size) / 2); 
            Br = floor((new_size - roi_size) / 2); %effective boundary width (absorbing boundaries + padding)
            
            % the boundaries are added to both sides. Remember where is the region of interest
            roi = {Bl(1)+(1:roi_size(1)), Bl(2)+(1:roi_size(2)), Bl(3)+(1:roi_size(3))};
            e_r_full = padarray(e_r, Bl, 'replicate', 'both');
            e_r_full = e_r_full(1:new_size(1), 1:new_size(2), 1:new_size(3)); %remove last single row/column when pad size is odd
        end
        
        function [e_r, leakage] = add_absorbing_boundaries(e_r, Bl, Br, options)
            %only for (now deprecated) PML boundary conditions:
            %Adds absorption in such a way to minimize reflection of a 
            %normally incident beam
            %
            if (~strcmp(options.boundary_type(1:3), 'PML') || all(Bl==0)) 
                leakage = [];
                return;
            end
            %the shape of the boundary is determined by f_boundary_curve, a function
            %that takes a position (in pixels, 0=start of boundary) and returns
            %Delta e_r for the boundary. 
            Bmax = max(Br); %used to calculate expected amount of leakage through boundary
            %todo: e_0 per row/column? or per side?
            e_0 = mean(e_r(:));
            k0 = sqrt(e_0)*2*pi/ (options.lambda / options.pixel_size); %k0 in 1/pixels
            % maximum value of the boundary (see Mathematica file = c(c-2ik0) = boundary_strength)
            % ||^2 = |c|^2 (|c|^2 + 4k0^2)   [assuming c=real, better possible when c complex?]
            % when |c| << |2k0| we can approximage: boundary_strength = 2 k0 c
            c = options.boundary_strength*k0^2 / (2*k0);
            switch (options.boundary_type)
                %case 'PML' %Nth order smooth?
                %    N=3;
                %    f_boundary_curve = @(r) 1/k0^2*(c^(N+2)*r.^N.*(N+1.0+(2.0i*k0-c)*r)) ./ (factorial(N)*exp(c*r));
                %    obj.leakage = exp(-c*Bmax)*exp(c*Bmax);
                case 'PML5' %5th order smooth
                    f_boundary_curve = @(r) 1/k0^2*(c^7*r.^5.*(6.0+(2.0i*k0-c)*r)) ./ (720+720*c*r+360*c^2*r.^2+120*c^3*r.^3+30*c^4*r.^4+6*c^5*r.^5+c^6*r.^6);
                    leakage = exp(-c*Bmax)*(720+720*c*Bmax+360*c^2*Bmax.^2+120*c^3*Bmax.^3+30*c^4*Bmax.^4+6*c^5*Bmax.^5+c^6*Bmax.^6)/24;
                case 'PML4' %4th order smooth
                    f_boundary_curve = @(r) 1/k0^2*(c^6*r.^4.*(5.0+(2.0i*k0-c)*r)) ./ (120+120*c*r+60*c^2*r.^2+20*c^3*r.^3+5*c^4*r.^4+c^5*r.^5);
                    leakage = exp(-c*Bmax)*(120+120*c*Bmax+60*c^2*Bmax.^2+20*c^3*Bmax.^3+5*c^4*Bmax.^4+c^5*Bmax.^5)/24;
                case 'PML3' %3rd order smooth
                    f_boundary_curve = @(r) 1/k0^2*(c^5*r.^3.*(4.0+(2.0i*k0-c)*r)) ./ (24+24*c*r+12*c^2*r.^2+4*c^3*r.^3+c^4*r.^4);
                    leakage = exp(-c*Bmax)*(24+24*c*Bmax+12*c^2*Bmax.^2+4*c^3*Bmax.^3+c^4*Bmax.^4)/24;
                case 'PML2' %2nd order smooth
                    f_boundary_curve = @(r) 1/k0^2*(c^4*r.^2.*(3.0+(2.0i*k0-c)*r)) ./ (6+6*c*r+3*c^2*r.^2+c^3*r.^3);
                    leakage = exp(-c*Bmax)*(6+6*c*Bmax+3*c^2*Bmax.^2+c^3*Bmax.^3)/6;
                case 'PML1' %1st order smooth
                    f_boundary_curve = @(r) 1/k0^2*(c^3*r.*(2.0+(2.0i*k0-c)*r)) ./ (2.0+2.0*c*r+c^2*r.^2) / k0^2; %(divide by k0^2 to get relative e_r)
                    leakage = exp(-c*Bmax)*(2+2*c*Bmax+c^2*Bmax.^2)/2;
                otherwise
                    error(['unknown boundary type' obj.boundary_type]);
            end
            roi_size = size(e_r) - Bl - Br;
            y = [(Bl(1):-1:1), zeros(1, roi_size(1)), (1:Br(1))]';
            x = [(Bl(2):-1:1), zeros(1, roi_size(2)), (1:Br(2))];
            z = [(Bl(3):-1:1), zeros(1, roi_size(3)), (1:Br(3))];
            z = reshape(z, [1,1,length(z)]);
            e_r = e_r + f_boundary_curve(sqrt(simgrid.dist2_3d(x,y,z)));
        end
    end
end