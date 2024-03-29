###############################################################################
# make_map.pyx
###############################################################################
#
# Given a number of sources, array of fluxes for each source, template & 
# exposure maps, and user defined PSF, simulates and returns a counts map. The
# source positions are determined using a rejection sampling routine.
#
###############################################################################

import healpy as hp
import numpy as np

cimport numpy as np
cimport cython

import rej_samp as rs
import pdf_sampler

cdef extern from "math.h":
    double cos(double x) nogil
    double sin(double x) nogil

@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
@cython.initializedcheck(False)
cpdef run(int N, double[::1] flux_arr, double[::1] temp,
          double[:,::1] EXP_map, psf_r, double[::1] flux_frac,
          double r_ROI=np.nan, bint returnpsdat=False):
    """ For a given number of sources and fluxes, PSF, template, and exposure
        map, create a simulated counts map.

            :param N: number of sources
            :param flux_arr: array source fluxes
            :param temp: numpy array for template
            :param EXP_map: numpy array of exposure map
            :param psf_r: user defined point spread function
            :param flux_frac: array of flux fractions to distribute between
                different energy bins, default is 1 bin
            :params r_ROI: maximum distance to draw sources from the galactic
                center
            :params returnpsdat: if true return data on the individual sources

            :returns: array of simulated counts map
    """
    cdef int NSIDE = hp.npix2nside(len(temp))
    cdef int num_phot, i, j, posit, iebin
    cdef int ebins = len(flux_frac)
    cdef np.ndarray[double,ndim=1,mode="c"] dist
    cdef double[:,::1] map_arr = np.zeros((ebins,len(temp)))
    cdef double th, ph
    psdat = []

    print("Simulating counts map ...")

    # Sample the radial PSF to later determine placement of photons.
    f = np.linspace(0,np.pi,1000000)
    pdf_psf = f * psf_r(f)
    pdf = pdf_sampler.PDFSampler(f,pdf_psf)

    # For each source find a source postion, determine number of photons, and 
    # their positions using angular distances drawn from the radial PSF. Add 
    # photons to a running counts map array, map_arr.
    i = 0
    while i < N:
        # Find random source position using rejection sampling.
        th, ph = np.asarray(rs.run(temp, r_ROI=r_ROI))

        # Create a rotation matrix for each source.
        # Shift phi coord pi/2 to correspond to center of HEALPix map durring
        # rotation.
        phm = ph + np.pi/2.
        # Each source is intially treated as being located at theta=0,phi=0 as 
        # the drawn PSF distances simply corresponds to photon theta positon.
        # A random phi value [0,2pi] is then drawn. Each photon is then rotated
        # about the x axis an angle corresponding to the true theta position of
        # the source, followed by a rotation about the z axis by the true phi
        # position plus an additional pi/2 radians.
        rotx = np.matrix([[1,0,0],[0,cos(th),-sin(th)],[0,sin(th),cos(th)]])
        rotz = np.matrix([[cos(phm),-sin(phm),0],[sin(phm),cos(phm),0],[0,0,1]])

        # Loop through energy bins
        iebin = 0
        while iebin < ebins:
            # Find expected number of source photons and then do a Poisson draw.
            # Weight the total flux by the expected flux in that bin
            num_phot = np.random.poisson(flux_arr[i] * flux_frac[iebin] *
                                    EXP_map[iebin,hp.ang2pix(NSIDE,th,ph)])

            if returnpsdat:
                psdat.append([th, ph,
                              num_phot, 
                              flux_arr[i]*flux_frac[iebin]*
                              EXP_map[iebin,hp.ang2pix(NSIDE,th,ph)],
                              flux_arr[i]*flux_frac[iebin]])

            # Sample distances from PSF for each source photon.
            dist = pdf(num_phot)

            j = 0
            while j < num_phot:
                # Draw a random phi postion [0,2pi].
                randPhi = 2*np.pi*np.random.random()
                # Convert the theta and phi to x,y,z coords.
                X = np.matrix(hp.ang2vec(dist[j],randPhi)).T
                # Rotate coords over the x axis.
                Xp = rotx*X
                # Rotate again, over the z axis.
                Xp = rotz*Xp
                Xp = np.array(Xp)
                # Determine pixel location from x,y,z values.
                posit = hp.vec2pix(NSIDE,Xp[0],Xp[1],Xp[2])
                # Add a count to that pixel on the map.
                map_arr[iebin,posit] += 1
                j += 1
            iebin += 1
        i += 1

    return np.array(map_arr), np.array(psdat)
