; NOM: mini-pong
; DESCRIPTION: Jeux mini-pong 16x21 pixels sur pic10f322
;              sortie vid�o NTSC
;              sortie audio
;              pointage indiqu� en haut de l'�cran
;              chaque joueur contr�le sa raquette � l'aide
;              de 2 boutons
;              au d�marrage la joeur de gauche a le service
;              et doit d�placer sa raquette pour d�marrer la partie
;
;              Le TIMER2 g�n�re le signal de synchronisation NTSC
;              et une interruption est g�n�rer � la fin de chaque
;              cycle. Toute la logique du programme s'ex�cute
;              � l'int�rieur de cette interruption.
;              la variable 'ln_cnt' compte les lignes de scan vid�o NTSC
;              mais est utilis�e aussi par le c�duleur de t�ches.
;              le NCO g�n�re le son produit lorsque la balle rebondi sur
;              une raquette ou un bord ainsi que le son plus grave et prolong�
;              lorsqu'un joueur manque la balle.
;
; AUTEUR: Jacquees Desch�nes
; DATE: 2013-08-10

    include <p10f322.inc>
    include "include\pic10f322_m.inc"
    radix dec

    __config _FOSC_INTOSC & _MCLRE_OFF & _LVP_OFF & _WDTE_OFF & _CP_ON

; constantes
#define PWM_PERIOD 254  ; peut n�cessiter un ajustement de quelques unit�s (252-255)
                        ; d�pend de la fr�quence du HFOSC qui peut varier
                        ; d'un MCU � l'autre.
#define SYNC_WIDTH  75  ; largeur de l'impulsion de synchronisation horizontale
                        ; signal NTSC.

; indicateurs bool�ens dans variable 'flags'
#define F_BIT9 0  ; 9i�me bit de ln_cnt
#define F_VIDEO 1 ; affichage actif
#define F_TONE 2  ; son actif
#define F_PAUSE 3 ; action arr�t�e
#define F_SERVE 4 ; qui a le service, 0 gauche, 1 droite
#define F_SCORE 5 ; 0 point � gauche, 1 point � droite
#define F_RMOVED 6 ; joueur de droit a boug� sa raquette
#define F_LMOVED 7 ; joueur de gauche a boug� sa raquette


#define VIDEO_OUT RA0  ; sortie signal vid�o
#define SYNC_OUT  RA1  ; sortie synchronisation NTSC
#define AUDIO_OUT RA2  ; sortie audio
#define DOWN_BTN RA2   ; bouton d�placement vers le bas
#define UP_BTN RA3     ; vers le haut

#define BALL_DLY  7     ; d�termine la vitesse de la balle
#define SCORE_TONE 30   ; tonalit� lorsqu'un point est compt�
#define SCORE_LENGTH 50 ; dur�e de la tonalit�
#define PING_TONE 58    ; tonalit� lorsque la balle frappe la raquette ou rebondie.
#define PING_LENGTH 6   ; dur�e
#define BTN_DLY 12       ; d�termine la vitesse des raquettes

; macros

delay_us macro us ; d�lais en micro-secondes, overhead 250nsec.
    movlw us
    addlw H'FF'
    skpz
    goto $-2
    endm

tone macro freq   ; d�marre la tonalit�e
    set_nco_incr freq
    enable_nco_output
    bsf flags, F_TONE
    if freq==PING_TONE
    movlw PING_LENGTH
    else
    movlw SCORE_LENGTH
    endif
    movwf tone_length
    bcf TRISA, AUDIO_OUT
    endm

wait_count macro count ; attend que TMR2 est atteint le compte
    movlw count
    subwf TMR2,W
    skpc
    goto $-3
    endm

; variables
    udata MINRAM
disp res 42  ; m�moire bitmap affichage 16x21 pixels
LScore res 1    ; pointage joueur de gauche
RScore res 1    ; pointage joueur de droite
flags res 1   ; indicateurs bool�ens
ln_cnt res 1  ; compteur lignes scan NTSC, 9i�me bit dans 'flags'
ballx res 1 ; position horizontale de la balle
bally res 1 ; position verticale de la balle
dx  res 1 ; delta x d�placement balle {-1,0,1}
dy  res 1 ; delta y d�placement balle {-1,0,1}
ball_speed res 1 ; vitesse de la balle, multiple de 16,7msec
tone_length res 1 ; dur�e de la tonalit�
btn_dly res 1   ; d�lais lecture boutons
LPaddle res 1   ; position raquette joueur de gauche
RPaddle res 1   ; position raquette joueur de droite
temp res 1      ; 3 variables temporaires
temp2 res 1
temp3 res 1

    code
    org 0
rst_vector
    clrf OPTION_REG
    bsf WPUA, RA3
    goto init

    org 4
isr_vector
    movlw 1
    incf ln_cnt
    skpnz
    xorwf flags
    ; c�duleur de t�che
    btfsc flags, F_VIDEO
    goto video_output
    btfss flags, F_BIT9
    goto $+5
    movlw 6
    subwf ln_cnt, W
    skpnz
    goto sync_start
    movlw 1
    subwf ln_cnt, W
    skpnz
    goto update_score
    movlw 3
    subwf ln_cnt, W
    skpnz
    goto sync_end
    movlw 6
    subwf ln_cnt, W
    skpnz
    goto move_ball
    movlw 7
    subwf ln_cnt, W
    skpnz
    goto read_buttons
    movlw 29
    subwf ln_cnt, W
    skpnz
    goto disp_start
    goto isr_exit ; aucune t�che � accomplir
read_buttons
    btfsc flags, F_TONE
    goto isr_exit
    movf btn_dly, F
    skpnz
    call buttons
    goto isr_exit
move_ball
    btfss flags, F_PAUSE
    call ball_control
    goto isr_exit
video_output
    movlw 198
    subwf ln_cnt, W
    skpnz
    goto disp_end
    call video
    goto isr_exit
sync_start
    set_pwm_duty_cycle PWM_CH2, ((PWM_PERIOD<<2)-SYNC_WIDTH)
    movf ball_speed, F
    skpz
    decf ball_speed
    movf btn_dly, F
    skpz
    decf btn_dly, F
    btfss flags, F_TONE
    goto $+5
    decfsz tone_length
    goto $+4
    bcf flags, F_TONE
    disable_nco_output
    bsf TRISA, AUDIO_OUT
    clrf ln_cnt
    bcf flags, F_BIT9
    call draw_table
    goto isr_exit
sync_end
    set_pwm_duty_cycle PWM_CH2, SYNC_WIDTH
    goto isr_exit
update_score
    call draw_score
    goto isr_exit
disp_start
    bsf flags, F_VIDEO
    goto isr_exit
disp_end
    bcf flags, F_VIDEO
draw_side
    wait_count 67
    goto $+1  ; d�lais suppl�mentaire
    bcf TRISA, VIDEO_OUT
    bsf PORTA, VIDEO_OUT
    wait_count 208
    bcf PORTA, VIDEO_OUT
    bsf TRISA, VIDEO_OUT
isr_exit
    bcf PIR1, TMR2IF
    retfie

; table des glyphes pour les caract�res
; num�rique, 2 digits compress�s dans
; 5 octets
digits
    addwf PCL, F
    dt  H'44',H'AC',H'A4',H'A4',H'4E' ; 0, 1
    dt  H'EE',H'22',H'CC',H'82',H'EE' ; 2, 3
    dt  H'AE',H'A8',H'EE',H'22',H'2E' ; 4, 5
    dt  H'CE',H'82',H'E2',H'A2',H'E2' ; 6, 7
    dt  H'EE',H'AA',H'EE',H'A2',H'E6' ; 8, 9

;******************************
; video, g�n�re la sortie vid�o
; entr�e: disp est le bitmap
;         contenant les pixels
;         � afficher
;*******************************
video
    movlw 30+40
    subwf ln_cnt, W
    skpnz
    goto draw_side
    wait_count 48
    movlw 30
    subwf ln_cnt, W
    movwf FSR
    bcf TRISA, VIDEO_OUT
    movlw 8
    movwf temp
    clrf temp2
    clrc
    rrf FSR, F
    clrc
    rrf FSR, F
    bcf FSR, 0 ; d�but � l'octet pair
    movlw disp
    addwf FSR, F
    movfw INDF
    movwf temp3
pixel_loop
    rlf temp3, F
    rlf temp3, W
    andlw 1
    addlw 2
    movwf PORTA
    decfsz temp, F
    goto pixel_loop
    btfsc temp2, 0
    goto video_exit
    bsf temp2, 0
    incf FSR
    movfw INDF
    movwf temp3
    movlw 8
    bcf PORTA, VIDEO_OUT
    bsf PORTA, VIDEO_OUT
    movwf temp
    bcf PORTA, VIDEO_OUT
    goto pixel_loop
video_exit
    delay_us 1
    bcf PORTA, VIDEO_OUT
    bsf TRISA, VIDEO_OUT
    return

;***********************************
; arr�te l'action suite en attente
; du service
; les raquette sont plac�es � mi-hauteur
;***********************************
set_pause
    bsf flags, F_PAUSE
    movlw 7
    movwf bally
    movlw 6
    movwf LPaddle
    movwf RPaddle
    movlw 1
    movwf ballx
    movwf dx
    btfss flags, F_SERVE
    return
    movlw 14
    movwf ballx
    comf dx
    incf dx
    return


;*********************************
; bound_paddle, s'assure que les raquettes
; demeure dans les limites de la table
; entr�e: W contient le pointeur de la raquette
;         � v�rifier
;*****************************************
bound_paddle    
    movwf FSR   
    btfsc INDF, 7
    clrf INDF
    movlw 14
    subwf INDF, W
    skpz
    return
    movlw 13
    movwf INDF
    return

;********************************
; buttons, fait la lectures des boutons
; de contr�le du jeux.
; La lecture se fait dans l'intervalle
; ou l'affichage vid�o est inactif.
; la sortie vid�o (RA0) est utilis�e pour
; contr�ler quel boutons sont lus, i.e.
; gauche ou droite.
;*********************************
buttons  
    bcf flags, F_RMOVED
    bcf flags, F_LMOVED
    bcf PORTA, RA0
    bcf TRISA, RA0 ; mode sortie
    delay_us 4
    ; lecture boutons de droite
    movfw PORTA
    movwf temp
    ; lecture boutons de gauche
    bsf PORTA, RA0
    delay_us 4
    movfw PORTA
    movwf temp2
    ; remet le port � l'�tat initial
    bsf TRISA, RA0
    bcf PORTA, RA0
    ; v�rification �tat boutons de droite.
    btfsc temp, RA3
    goto $+3
    decf RPaddle
    bsf flags, F_RMOVED
    btfsc temp, RA2
    goto $+3
    incf RPaddle
    bsf flags, F_RMOVED
    ; v�rification �tat boutons de gauche
    btfsc temp2, RA3
    goto $+3
    decf LPaddle
    bsf flags, F_LMOVED
    btfsc temp2, RA2
    goto $+3
    incf LPaddle
    bsf flags, F_LMOVED
buttons_exit
    movlw RPaddle
    call bound_paddle
    movlw LPaddle
    call bound_paddle
    btfss flags, F_PAUSE
    return
    movlw (1<<F_RMOVED)|(1<<F_LMOVED)
    andwf flags, W
    skpnz
    return
    btfss flags, F_SERVE
    goto test_left_moved
    btfsc flags, F_RMOVED
    bcf flags, F_PAUSE
    return
test_left_moved
    btfsc flags, F_LMOVED
    bcf flags, F_PAUSE
    return

;********************************
; set_dy, d�termine la valeur de dy
; si la balle est pass� au dessus du centre de la raquette
; elle repart vers le haut (dy=-1)
; si la balle frappe la raquette au centre elle
; repart en ligne droite (dy=0)
; si elle est au dessous du centre elle repart
; vers le bas (dy=1)
; entr�e: W = pointeur raquette qui a re�ue la balle
;*********************************
set_dy  
    movwf FSR
    movfw INDF
    addlw 1
    subwf bally, W
    skpnz
    return
    skpnc
    movlw -1
    skpc
    movlw 1
    movwf dy
    return

;*******************************
; ball_control, controle le mouvement
; de la balle en la faisant rebondir
; sur les raquettes et sur les bords
; haut et bas de la table.
;*******************************
ball_control
    movf ball_speed, F
    skpz
    return
    movlw BALL_DLY
    movwf ball_speed
    movfw dx
    addwf ballx
    movfw dy
    addwf bally
check_y_bounds
    skpnz
    goto invert_dy
    movlw 15
    subwf bally, W
    skpc
    goto check_x_bounds
invert_dy
    comf dy, F
    incf dy, F
    tone PING_TONE
check_x_bounds
    movf ballx, F
    skpnz
    goto invert_dx
    movlw 15
    subwf ballx,W
    skpc
    return
invert_dx
    comf dx
    incf dx
    tone PING_TONE
    movf ballx, F
    skpnz
    goto check_left_collision
; a atteint le c�t� droit
    movfw RPaddle
    call set_dy
    movfw RPaddle
    subwf bally, W
    skpc
    goto right_missed
    movlw 3
    addwf RPaddle, W
    subwf bally, W
    skpnc
    goto right_missed
    return
check_left_collision ; a atteint le c�t� gauche
    movfw LPaddle
    call set_dy
    movfw LPaddle
    subwf bally, W
    skpc
    goto left_missed
    movlw 3
    addwf LPaddle, W
    subwf bally, W
    skpnc
    goto left_missed
    return
left_missed
    bsf flags, F_SCORE
    call player_score
    return
right_missed
    bcf flags, F_SCORE
    call player_score
    return

;*********************************
; inc_score, incr�mente le pointage
; du joueur qui a gagn� l'�change.
; fait l'ajustement B.C.D. du compte.
; entr�e: W contient le pointeur du
;         joueur qui gagn� l'�change.
;**********************************
inc_score
    movwf FSR
    incf INDF
    movfw INDF
    andlw 15
    sublw 9
    skpnc
    return
    movlw H'F0'
    andwf INDF
    movlw H'10'
    addwf INDF
    movlw H'A0'
    subwf INDF,W
    skpnz
    clrf INDF
    return

;************************************
; player_score, v�rifie � qui va le point
; et appelle inc_score avec le pointeur
; du joueur gagnant.
; appel set_pause pour arr�ter l'action
; en attente du prochain service.
;*************************************
player_score 
    bcf flags, F_SERVE
    btfss flags, F_SCORE ; 0 gauche, 1 droite
    goto left_score
    bsf flags, F_SERVE
    movlw RScore
    goto $+2
left_score
    movlw LScore
    call inc_score
    tone SCORE_TONE
    call set_pause
    return

;**************************
; draw_lpaddle, dessine la
; raquette de gauche
;**************************
draw_lpaddle     ; dessine raquette de gauche
    movlw disp+10
    movwf FSR
    clrc
    rlf LPaddle, W
    addwf FSR
    movlw 128
    goto draw_paddle

;****************************
; draw_rpaddle, dessine la
; raquette de droite.
;****************************
draw_rpaddle     ; dessine raquette de droite
    movlw disp+11
    movwf FSR
    clrc
    rlf RPaddle, W
    addwf FSR
    movlw 1
draw_paddle
    iorwf INDF
    incf FSR
    incf FSR
    iorwf INDF
    incf FSR
    incf FSR
    iorwf INDF
    return

;****************************
; draw_ball, dessine la balle
; sur la table
;****************************
draw_ball       ; 24 cycles avec appel et retour
    movlw disp+10 ; les 10 premiers octets utilis� pour l'affichage du pointage
    movwf FSR
    clrc
    rlf bally, W  ; 2 octets par ligne, donc d�placement = y*2
    addwf FSR
    btfsc ballx, 3 ; si >7
    incf FSR       ; octet suivant
    movlw 128      ; position de la balle dans l'octet
    movwf temp     ; rotation jusqu'� la bonne position
    movfw ballx
    andlw 7        ; W= compte des rotations
    skpnz
    goto $+6
    clrc
    rrf temp
    addlw H'FF'   ; W--
    skpz
    goto $-4
    movfw temp
    iorwf INDF, F
    return

;********************
;clear_disp
;efface l'affichage
;********************
clear_disp    ; 168 cycles avec appel et retour
    movlw disp
    movwf FSR
    movlw 42
    movwf temp
    clrf INDF
    incf FSR
    decfsz temp
    goto $-3
    return

;***********************
; draw_table, dessine
; la table en appellant
; les routines pour chaque
; �l�ment la composant.
;************************
draw_table              ; 230 avec appel et retour
    call clear_disp     ; 168
    call draw_lpaddle      ; 17
    call draw_rpaddle      ; 17
    call draw_ball      ; 24
    return              ; 2

;***********************************
; digit_offset, calcule la position
;   position = digit * 10 / 2
; dans la table 'digits' pour chaque digit
; entr�e: W contient le digit dans
;         les 4 bits faibles
; sortie: W contient le d�placement dans
;         la table 'digits'
; utilise temp2
;***********************************
digit_offset    
    andlw H'E'  
    movwf temp2 
    clrc
    rlf temp2, F
    rlf temp2, F
    addwf temp2, F
    rrf temp2, W
    return

;********************************************
; digit_row, affiche une ligne des 2 digits
;            du pointage.
; entr�e: temp3, contient le pointage
;         temp, contient la rang�e du glyphe (0-5)
; utilise temp2
;********************************************
digit_row
    swapf temp3, W   ; digit dizaine
    call digit_offset
    addwf temp, W    ; ajoute d�placement pour la rang�e
    call digits
    movwf temp2     ; bitmap pour cette rang�e
    btfsc temp3, 4  ; si digit pair prend les 4 bits forts
    swapf temp2, W  ; si impair prend les 4 bits faibles.
    andlw H'F0'
    iorwf INDF
digit2  ; digit unit�s
    movfw temp3
    call digit_offset
    addwf temp, W
    call digits
    movwf temp2
    btfss temp3, 0
    swapf temp2, W
    andlw H'F'
    iorwf INDF
    return

;***********************************
; draw_score, affiche les glyphes du pointage
; de chaque joueur. L'affichage se fait par
; rang�e, i.e. la premi�re rang�e des 4 glyphes
; est affich�e ensuite la 2i�me, etc.
; utilse: temp comme compteur de rang�e
;         temp3 contient le pointage
;         FSR pointe la m�moire vid�o 'disp'
;************************************
draw_score
    movlw disp
    movwf FSR
    clrf temp  ; compteur lignes du glyphe
next_row
    movfw LScore
    movwf temp3
    call digit_row
    incf FSR
    movfw RScore
    movwf temp3
    call digit_row
    incf FSR
    incf temp
    movlw 5
    subwf temp,W
    skpz
    goto next_row
    return

; initialiation du programme.
init
    set_clk_freq D'16'
    clrf ANSELA
; zero RAM
    movlw MINRAM
    movwf FSR
    clrf INDF
    incf FSR
    btfss FSR, 7
    goto $-3
; initialisation NCO
    set_nco_clock NCO_CLK_INTOSC
    enable_nco
; initialisation PWM1
    movlw PWM_PERIOD
    movwf PR2
    bcf TRISA, SYNC_OUT
    set_pwm_polarity  PWM_CH2, PWM_POL_L
    enable_pwm_output PWM_CH2
    enable_pwm_channel PWM_CH2
    enable_tmr2_int
    enable_periph_int
    call set_pause
    bsf T2CON, TMR2ON
    enable_interrupt

; il ne se passe rien dans la proc�dure
; principale car tout est fait pendant
; l'interruption du TIMER2
main
    goto main 
    end




