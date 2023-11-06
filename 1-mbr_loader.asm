
;此程序为MBR和加载器
;当前并能动态的知道操作系统哪块内存是空闲, 因此假设0x10000处是空闲的
;也不能动态的识别用户程序到底放在哪里,因此假设放在逻辑扇区号100的地方
;按道理说0x7c00+此扇区512字节 = 0x7e00. 即0000:7e00 后可以放用户程序
;但此程序中还需要用到栈, 栈段也放在此段中 0 ~ 0xffff, 虽然跟代码混在一起,但需要push的并不多.
;因此直接0xffff+1 的位置用来给用户程序

;分段读取用户程序
;由于用户程序可能超过65536字节,如果不改变段地址,偏移地址最多65536,因此无法完整读取
;所以下面采用改变段地址的方式来读取,每读一个扇区(512字节),段地址就增加0x20
;比如一开始段地址0x1000, 读取一次后, 把 0x1000+0x20 当成段地址来读取下个扇区,这样就不需要考虑偏移地址的问题

;用户程序的重定位问题
;每个SECTION在编译时候的段地址都是相对于文件首的偏移量(还会根据align来对齐)
;在加载到内存后, 段地址需要根据加载位置(当前是0x10000物理地址,即0x1000:0000)来重新计算
;比如当前的加载位置是0x1000:0x0000 
    ;假设用户section header 原段地址:0x00   ,  加载后段地址:0x1000 + 0x0000
    ;假设用户section data   原段地址:0x20   ,  加载后段地址:0x1000 + 0x20
    ;假设用户section code   原段地址:0x30   ,  加载后段地址:0x1000 + 0x30... 以此类推
;在计算完实际内存段地址后, 需要把原来的文件内段地址 修改成 内存段地址, 以便用户程序能找到实际段地址, 即需要修改用户头部


;假设用户程序放在逻辑扇区号100的地方
USER_APP_LBA EQU 100

;MBR会由BIOS自动加载到0x7c00处
;vstart=0x7c00 代码里的偏移就不需要额外+0x7c00
SECTION mbr align=16 vstart=0x7c00

    ;计算用户程序的段地址
    mov ax,[cs:USER_APP_BASE]   
    mov dx,[cs:USER_APP_BASE + 2]
    mov bx,16
    div bx
    mov ds,ax                   ;获取用户程序固定的段地址,也就是必然会加载到这个位置


    ;设置ss,sp , 假设栈段在 0x0 ~ 0xffff , 即栈顶的第一个元素是 0:0xfffe
    xor ax,ax
    mov ss,ax
    mov sp,ax


    ;先读取用户程序头部,用于分析程序需要读取几个扇区,对应着用户程序头部的字节数
    ;读取硬盘是以一个扇区来读取的, 一个扇区512字节
    ; read_sector 参数: 逻辑扇区16高位,逻辑扇区低16位, 目标段地址, 目标偏移地址
    ;参数从右往左入栈 ,相当于 read_sector(0,USER_APP_LBA,ds,0)

    push word 0                 ;目标偏移地址
    push ds                     ;目标段地址
    push word USER_APP_LBA      ;扇区低16位
    push word 0                 ;扇区高16位,只有高12位有效, LBA只有28位
    call read_sector            ;push ip ; jmp read_sector
    add sp,8            ;恢复栈 , 2*4字节


    ;ds : 0x1000
    ;根据用户程序头部的字节数算出一共需要读取几个扇区
    ;由于读取硬盘都是以一个扇区(512字节)为单位 . 如果程序长度为513字节,则需要读取2个扇区

    mov ax,[ds:0]       ;读取用户程序头部user_app_len的低16位
    mov dx,[ds:2]       ;user_app_len 高16位
    mov cx,512    
    div cx
    cmp dx,0            ;余数如果不为0,则扇区需要额外+1,但由于上面已经读过一个扇区,因此不需要加
    jnz .check_left_sector
    dec ax              ;余数=0, 则-1扇区数, 之前已经先过一个扇区

    .check_left_sector:
        cmp ax, 0       ;判断剩余扇区数量是否为0, 如果为0则说明读完
        jmp .read_done

        ;ax != 0 读取剩余扇区
        mov cx, ax              ;cx剩余扇区数量
		mov ax,ds
        mov es,ax               ;es 用于修改段地址
        mov si,USER_APP_LBA     ;此扇区号已经在上面读取过

    ;读取剩余扇区,每次把段地址+0x20(相当于实际增加512字节), 不需要考虑偏移地址的问题了
    .read_left_sector:
        mov ax,es
        add ax,0x20
        mov es,ax       ;使用新的段地址来读取
        inc si          ;从下一个扇区号开始读取

        push word 0     ;每一次的目标偏移都从0 , 因为已经从段地址增加了0x20
        push es         ;段地址
        push si         ;扇区低16位
        push word 0     ;扇区高16位
        call read_sector
        add sp,8        ;恢复栈
        loop .read_left_sector

    ;全部读完
    ;用户程序段的重定位
    ;ds 相当指向加载首地址: 0x1000
    ;把用户程序内的原文件内段地址修改成实际内存段地址
    .read_done:
        mov cx, [ds:0x1c]               ;获取重定位表数量
        mov bx, 0x0a               ;获取重定位表起始地址

        ;循环重定位, 替换成实际内存段地址
        .realloc_table:
            mov ax,[ds:bx]              ;文件内段低位
            mov dx,[ds:bx + 2]          ;文件内段高位
            push dx
            push ax
            call convert_fileSectionAddr    ;把文件内32位段地址转成加载后的内存逻辑段地址
            add sp,4
            mov [ds:bx],ax              ;把段地址写回用户程序
            mov word [ds:bx + 2],0      ;高位清0即可
            add bx,4
        loop .realloc_table

        ;入口段地址重定位, 以便跳转到用户程序
        push word [ds:0x08]
        push word [ds:0x06]            
        call convert_fileSectionAddr
        add sp,4
        mov word [ds:0x08],0
        mov word [ds:0x06],ax
    
        
        
    ;在当前栈中存放当前MBR的 ds, cs, 返回地址.   用于返回
    push ds
    push cs
    push word exit

    ;把当前栈写入用户程序,用于切换栈,返回
    mov word [ds:0x1e],sp
    mov word [ds:0x20],ss
    
        
    ;跳转到用户程序
    jmp far [ds:0x04]       ;0x04 偏移 , 0x06 段地址


    exit:
    ;返回当前程序
    pop ds          ;恢复MBR的ds
    jmp $



;=====================================================================
;把文件内的32位段地址转成16位逻辑段地址
;参数: 低16位段地址, 高16位段地址
;返回: ax 16位逻辑段地址

;32位段地址中只有低20位有效
convert_fileSectionAddr:
    push bp
    mov bp,sp
    push dx
    
    mov ax,[bp + 4]  ;低16位段地址
    mov dx,[bp + 6]  ;高16位段地址
    add ax,[cs:USER_APP_BASE]   ;低位与低位相加
    adc dx,[cs:USER_APP_BASE+2] ;高位相加


    shr ax,4         ;低位除以16
    shl dx,12        ;高16位中只有低4位为有效位
    and dx,0xf000    ;确保只有高4位有效
    or ax,dx         ;合并

    
    pop dx
    mov sp,bp
    pop bp
    ret


;===================================================================================
;读取一个扇区
;参数 : 逻辑扇区16高位,逻辑扇区低16位, 目标段地址, 目标偏移地址

;需要用到的端口号 0x1f2 ~ 0x1f7 , 0x1f0
;端口 0x1f2 = 设置扇区数量
;LBA28有28位 扇区号
;0x1f3 ~ 0x1f6 设置逻辑扇区号, 这些端口都是8位端口,因此只能传送一个字节来满足28位扇区号
;0x1f6端口只有低4位是端口号,高前3位111表示LBA模式,后1位表示主盘(0)从盘(1)
;0x1f7 用于读写命令,以及读取硬盘状态
;一般情况下先检测0x1f7的状态,检测第7位(是否繁忙)和第3位(准备交换数据)的状态
;即检测 : 1000_1000b  与 0x1f7读取回来的状态, 如果 1000_1000b and 状态 = 0000_1000b 则可以读写
;0x1f0用于读写数据, 这是一个16位端口

read_sector:
    push bp
    mov bp,sp           ;bp + 2 是IP的位置, bp + 4 是第一个参数
    push ds
    push bx
    push si
    push di
    push ax
    push dx
    push cx

    mov di,[bp + 4]     ;扇区高16位
    mov si,[bp + 6]     ;扇区低16位
    mov ax,[bp + 8]     ;目标段地址
    mov ds,ax
    mov bx,[bp + 10]    ;目标偏移地址

    mov dx, 0x1f2       ;设置扇区数量
    mov al,1
    out dx,al           

;设置扇区号
    inc dx              ;0x1f3
    mov ax,si           ;扇区低16位
    out dx,al           ;由于是8位端口, 先把al的传送过去

    inc dx              ;0x1f4
    mov al,ah
    out dx,al           ;低16位中的高8位

    inc dx              ;0x1f5
    mov ax,di
    out dx,al           ;高16位中的低8位

    inc dx              ;0x1f6
    mov al,0xe0         ;LBA模式,从主盘读取 1110_0000b
    or al,ah            ;ah中剩余的高4位
    out dx,al

    inc dx             ;0x1f7
;设置0x1f7 用于读取硬盘
    mov al,0x20          
    out dx,al

;读取0x1f7, 查看当前硬盘状态
    .read_disk_status:
        in al,dx            ;8位端口, 读取当前状态
        and al, 1000_1000b  ;检测是否可以读取硬盘了
        cmp al,0x08         ;如果状态是 0000_1000b则可以读取了
        jnz .read_disk_status

;开始读取硬盘, 端口0x1f0
    mov dx,0x1f0
    mov cx,256          ;循环256次,一次读取2个字节

    .begin_read:
        in ax,dx        
        mov [ds:bx], ax     ;把读取的2个字节复制到ds:bx处
        add bx,2
        loop .begin_read


    pop cx
    pop dx
    pop ax
    pop di
    pop si
    pop bx
    pop ds
    mov sp,bp
    pop bp
    ret
    



;假设用户程序放在这个内存地址
USER_APP_BASE dd 0x10000

times 510-($-$$) db 0
;0x55,0xaa 为MBR固定标识
dw 0xaa55
