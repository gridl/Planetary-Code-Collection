module body
  ! physical properties of the body 

  ! Moon
  real(8), parameter :: solarDay=86400.*29.53  ! (s)
  real(8), parameter :: g=1.62, Rmoon=1737.e3
  real(8), parameter :: dtsec=3600.  ! thermal model time step (s)
  real(8), parameter :: semia=1.  ! (AU)
  real(8), parameter :: zmax=0.5   ! domain depth for 1D thermal model, if used
  real(8), parameter :: albedo=0.11, emiss=0.95
  !real(8), parameter :: albedo=0.1, emiss=1.
  real(8), parameter :: Fgeotherm=0.018  ! Langseth et al. (1976)  (W/m^2)

  ! Mercury
  !real(8), parameter :: solarDay=4222.6*3600., semia=0.3871
  !real(8), parameter :: g=3.7, Rmoon=2440e3
  !real(8), parameter :: dtsec=3600.*12.
  !real(8), parameter :: zmax=1.5
  !real(8), parameter :: albedo=0.07, emiss=0.9
  !real(8), parameter :: Fgeotherm=0.

  ! Ceres
  !real(8), parameter :: solarDay=9.075*3600., semia=2.77
  !real(8), parameter :: g=0.27, Rmoon=480e3  !(975x909km)
  !real(8), parameter :: dtsec=600. 
  !real(8), parameter :: albedo=0.09, emiss=0.9
  !real(8), parameter :: zmax=0.5, Fgeotherm=0.
end module body


module exo_species
  real(8), parameter :: mmass = 18.015   ! H2O
  !real(8), parameter :: mmass = 19.021   ! HDO
  !real(8), parameter :: mmass = 17.007   ! OH
  !real(8), parameter :: mmass = 4.0026   ! He-4
  !real(8), parameter :: mmass = 39.962   ! Ar-40

  ! photodissociation time scale at 1 AU
  !real(8), parameter :: taudissoc = 20.*3600.  ! Potter & delDuca (1964)
  real(8), parameter :: taudissoc = 1/12.6e-6  ! Crovisier (1989)
  !real(8), parameter :: taudissoc = 1/23.0e-6  ! Crovisier (1989), active sun
  !real(8), parameter :: taudissoc = 1.9e7  ! He, Killen & Ip (1999)
  !real(8), parameter :: taudissoc = 3.2e6  ! Ar, Killen & Ip (1999)
end module exo_species


program allofmoon
!***********************************************************************
! surface temperatures of the Moon and migration of H2O
!***********************************************************************
  use grid
  use body, only : solarDay, dtsec, Rmoon
  implicit none

  integer, parameter :: Np=2000000  ! maximum number of computational particles

  integer n, i, nequil, k
  integer cc(6), cc_old(6), alive, cc_prod, cc_prod_total, cc_trapped, cc_destroyed
  integer :: idum=-92309   ! random number seed
  real(8) tmax, time, tequil
  real(8), dimension(veclen) :: Tsurf, Qn, sigma 
  real(8) residencetime, HAi 
  character(10) ext

  real(8), dimension(np,2) :: p_r ! longitude(1) and latitude(2)
  integer, dimension(np) :: p_s ! status 0=on surface, 1=inflight, <0= destroyed or trapped
  real(8), dimension(np) :: p_t ! time
  integer, dimension(np) :: p_n ! # of hops (diagnostic only)

  logical, external :: incoldtrap
  integer, external :: inbox, totalnr
  real(8), external :: flux_noatm, residence_time, ran2
  
  ! if you use Diviner surface temperature maps as input
  !integer, parameter :: NT=708  ! tied to timestep of 708/(29.53*86400.) = 3596 sec
  !real(8) lon(nlon),lat(nlat),Tbig(nlon,nlat,24)

  ! equilibration time for thermal model in solar days
  tequil=10.

  ! run time for hopping+thermal model in solar days
  tmax=4.
  !tmax=2./29.53
  !tmax = 2*86400./solarDay

  ! set some constants
  nequil=int(tequil*solarDay/dtsec)

  print *,'Model parameters:'
  print *,'Time step=',dtsec,'sec'
  print *,'Equilibration time',tequil,' lunar days'
  print *,'Maximum time',tmax,' lunar days',tmax*solarDay/(86400.*365.242),' years'
  print *,'grid size',nlon,'x',nlat,'veclen=',veclen
  print *,'number of molecules',np

  HAi = 0.  ! noon

  cc_trapped=0; cc_destroyed=0
  cc_prod_total=0
  p_n(:) = 0

  ! initial configuration
  !p_t(:)=0.;  p_s(:)=0    ! all particles on surface
  p_t(:)=1d99; p_s(:)=-9   ! no particles
  !do i=1,np
     !p_r(i,1)=360.*ran2(idum); 
     !p_r(i,1)=0.
     !p_r(i,2)=0.; 
  !enddo

  open(unit=20,file='Tsurface',status='unknown',action='write')
  open(unit=21,file='Tsurface_end',status='unknown',action='write')
  open(unit=30,file='series',status='unknown',action='write')
  open(unit=50,file='particles',status='unknown',action='write')
  open(unit=51,file='particles_end',status='unknown',action='write')

  ! if you work with real coldtrap contours
  !call readcontours
  
  ! if Diviner surface temperatures are read in
  !call readTmaps(nlon,nlat,lon,lat,Tbig)

  !-------loop over time steps 
  do n=-nequil,1000000
     time =(n+1)*dtsec   ! time at n+1 
     if (time>tmax*solarDay) exit

     !-- Temperature
     call SurfaceTemperature(dtsec,HAi,time,Tsurf,Qn)
     !call interpTmaps(nlon,nlat,NT,n,lon,Tbig,Tsurf,Qn)
     if (n<0) cycle   ! skip remainder

     ! some output
     call totalnrs(np,p_s,cc)
     print *,time/3600.,'One hour call',sum(cc(1:2))
     write(30,*) time/3600.,cc(1:2),cc_trapped

     ! create new particles
     call production(Np,p_r,p_s,idum,Tsurf,cc_prod)
     !cc_prod = 0
     cc_prod_total = cc_prod_total + cc_prod

     ! update residence times with new temperature
     do i=1,np
        if (p_s(i)==0) then ! on surface
           k = inbox(p_r(i,:))
           residencetime = residence_time(Tsurf(k))
           p_t(i) = residencetime   ! relative to time
        endif
     enddo
     
     if (n==0) then ! write out initial distribution
        !call writeparticles(50,np,p_r,p_s,p_t,p_n)
        call writeglobe(20,Tsurf)
     endif

     !write(ext,'(i6)') n
     write(ext,'(i0.4)') n
     call deblank(ext)
     !open(unit=27,file='particles.'//ext,status='unknown',action='write')
     !call writeparticles(27,np,p_r,p_s,p_t,p_n)
     !close(27)
     !open(unit=28,file='tsurf.'//ext,status='unknown',action='write')
     !call writeglobe(28,Tsurf)
     !close(28)
     !if (time>(tmax-1.)*solarDay) then
     !   call particles2sigma(Np,p_r,p_s,sigma)
     !endif

     ! 1 hour of hopping
     alive = count(p_s>=0)
     call totalnrs(Np,p_s,cc_old)
     call montecarlo(np,idum,p_r,p_s,p_t,p_n,Tsurf,dtsec,cc_trapped,Qn)
     !call destruction(np,p_r,p_s,p_t,idum,dtsec,veclen,sigma)
     cc_destroyed = cc_destroyed + alive - count(p_s>=0)

     call totalnrs(Np,p_s,cc)
     cc = cc-cc_old
     !write(52,*) cc_prod,cc(3:6)

  enddo
!50 continue
  call writeparticles(51,Np,p_r,p_s,p_t,p_n)
  call particles2sigma(Np,p_r,p_s,sigma)
  call writeglobe(21,Tsurf)

  call totalnrs(Np,p_s,cc)
  print *,'# particles on surface',cc(1)
  print *,'# particles in flight',cc(2)
  print *,'# particles destroyed, photo',cc(3)
  print *,'# particles destroyed, escape',cc(4)
  print *,'# particles destroyed',cc(3)+cc(4),cc_destroyed-cc_trapped
  print *,'# particles coldtrapped',cc(5)+cc(6),cc_trapped
  print *,'# particles produced',cc_prod_total
  !print *,'# ',Np,cc(3),cc(4),cc(5)+cc(6),cc(5),cc(6)
  print *,'# produced / surface density ',cc_prod_total,cc_prod_total/(4*pi*Rmoon**2)

  !print *, HAi, &
  !     & 'N=',count(p_s<=-3 .and. p_r(:,2)>0.), &
  !     & 'S=',count(p_s<=-3 .and. p_r(:,2)<0.)

  close(20); close(21)
  close(30)
  close(40); close(41)
end program allofmoon


subroutine writeglobe(unit,Tsurf)
  use grid, only: nlon, nlat, veclen
  implicit none
  integer, intent(IN) :: unit
  real(8), intent(IN) :: Tsurf(*)
  integer i,j,k
  real(8) longitude(nlon), latitude(nlat)

  ! set up lon-lat grid
  call lonlatgrid(longitude,latitude)

  if (veclen==nlon*nlat+2) write(unit,100) 0.,90.,Tsurf(1)
  do j=1,nlat
     do i=1,nlon
        if (veclen==nlon*nlat+2) then
           k = 1 + i + (j-1)*nlon 
        else
           k = i + (j-1)*nlon 
        endif
        write(unit,100) longitude(i),latitude(j),Tsurf(k)
     enddo
  enddo
  if (veclen==nlon*nlat+2) write(unit,100) 0.,-90.,Tsurf(veclen)
100 format (f5.1,1x,f6.2,1x,f7.3)
end subroutine writeglobe


subroutine deblank(chr)
! deblank string
! posted by James Giles at comp.lang.fortran on 3 August 2003.
  implicit none
  character(*), intent(inout) :: chr
  integer i, j, istart
  
  istart = index(chr, " ")
  if (istart == 0) return   ! no blanks in the argument
  
  j = istart-1  ! just before the first blank.
  
  do i = istart, len(trim(chr))
     if (chr(i:i) /= " ") then
        j = j+1
        chr(j:j) = chr(i:i)
     endif
  end do
  
  if(j < len(chr)) chr(j+1:) = " "  ! clear the rest of the string
  return
end subroutine deblank


subroutine SurfaceTemperature(dtsec,HAi,time,Tsurf,Qn)
  ! surface temperature model
  use body, only : solarDay, zmax, Fgeotherm, semia, albedo, emiss
  use grid, only : VECLEN
  implicit none
  real(8), intent(IN) :: dtsec, HAi, time
  real(8), intent(INOUT) :: Tsurf(veclen)
  real(8), intent(OUT) :: Qn(veclen)

  integer, parameter :: NMAX=1000
  real(8), parameter :: pi=3.1415926535897932, d2r=pi/180.
  real(8), parameter :: sigSB=5.67051d-8
  real(8), parameter :: zero=0.

  real(8), save :: ti(NMAX), rhocv(NMAX), z(NMAX)
  real(8), save :: T(NMAX,veclen)
  logical, save :: FirstCall = .TRUE.

  integer, parameter :: nz=30
  real(8), parameter :: zfac=1.07d0

  integer k, i
  real(8) thIn, rhoc, delta, decl, Qnp1, sunR
  real(8) lon,lat,HA,geof,Tmean,Fsurf
  !real(8) eps, ecc, omega, Ls

  real(8), external :: flux_noatm

  ! toy orbit
  decl = 0.
  sunR = semia
  ! less toy, but still toy
  !eps = 1.54*d2r    ! lunar obliquity to ecliptic
  !ecc=0.; omega=0.
  !call generalorbit(time/86400.,semia,ecc,omega,eps,Ls,decl,sunR)

  ! initialization
  if (FirstCall) then
     thIn= 50.;  rhoc=1000000.
     delta = thIn/rhoc*sqrt(solarDay/pi)  ! skin depth

     print *,'Thermal model parameters:'
     print *,'nz=',nz,' zmax=',zmax,' zfac=',zfac
     print *,'Thermal inertia=',thIn,' rho*c=',rhoc
     print *,'Geothermal flux=',Fgeotherm
     print *,'Diurnal skin depth=',delta
     print *,'Albedo=',albedo

     ! set up depth grid
     call setgrid(nz,z,zmax,zfac)
     if (z(6)>delta) then
        print *,'WARNING: less than 6 points within diurnal skin depth'
     endif
     do i=1,nz
        if (z(i)<delta) cycle
        print *,i-1,' grid points within diurnal skin depth'
        exit
     enddo
     if (z(1)<1.e-5) print *,'WARNING: first grid point is too shallow'
     
     ti(1:nz) = thIn
     rhocv(1:nz) = rhoc

     do k=1,veclen
        call k2lonlat(k,lon,lat)
        geof = cos(lat)/pi
        Tmean=(1370*(1.-albedo)*geof/sigSB)**0.25 - 10.
        if (.not. Tmean>0.) Tmean=(Fgeotherm/sigSB)**0.25  ! fixes nan and zero
        T(1:nz,k) = Tmean
        Tsurf(k) = Tmean
        HA=2.*pi*mod((time-dtsec)/solarDay+(lon-HAi)/360.,1.d0)    ! hour angle
        Qn(k)=(1-albedo)*flux_noatm(sunR,decl,lat,HA,zero,zero)
     enddo
  end if

  do k=1,veclen
     call k2lonlat(k,lon,lat)
     ! longitude of morning terminator = -time/solarDay + lon + HAi ??
     HA=2.*pi*mod(time/solarDay+(lon-HAi)/360.,1.d0)    ! hour angle
     Qnp1=(1-albedo)*flux_noatm(sunR,decl,lat,HA,zero,zero)
     call conductionQ(nz,z,dtsec,Qn(k),Qnp1,T(:,k),ti,rhocv,emiss, &
          & Tsurf(k),Fgeotherm,Fsurf)
     Qn(k)=Qnp1
  enddo

  FirstCall = .FALSE.
end subroutine SurfaceTemperature


subroutine particles2sigma(Np, p_r, p_s, sigma)
  use grid
  use body, only : Rmoon
  implicit none
  integer, intent(IN) :: Np, p_s(Np)
  real(8), intent(IN) :: p_r(Np,2)
  real(8), intent(OUT) :: sigma(veclen)
  integer i, k, nr0(veclen), nr1(veclen), totalnr0, totalnr1
  real(8) dA(veclen)
  logical, save :: FirstCall = .TRUE.
  integer, external :: inbox

  nr0(:)=0;  nr1(:)=0
  do i=1,Np
     if (p_s(i)==0) then
        k = inbox(p_r(i,:))
        nr0(k) = nr0(k)+1
     endif
     if (p_s(i)==1) then
        k = inbox(p_r(i,:))
        nr1(k) = nr1(k)+1
     endif
  enddo

  call areas(dA)
  dA = dA*Rmoon**2

  sigma(:) = nr0(:)/dA(:)
  !sigma(:) = nr1(:)/dA(:)  
  !print *,'total area',sum(dA)/(4*pi*Rmoon**2)  ! test
  totalnr0 = sum(nr0(:))
  totalnr1 = sum(nr1(:))
  !print *,'total # particles in particles2sigma:',Np,totalnr0  ! for checking purposes
  if (FirstCall) then 
     open(unit=40,file='sigma.dat',action='write')
     FirstCall = .FALSE.
  else
     open(unit=40,file='sigma.dat',action='write',position='append')
  endif
  write(40,'(999999(1x,g11.5))') sigma
  close(40)
end subroutine particles2sigma
