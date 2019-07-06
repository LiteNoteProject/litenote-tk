proc ::tcl::dict::getnull {dictionary args} {
    if {[exists $dictionary {*}$args]} {
        get $dictionary {*}$args
    }
}
namespace ensemble configure dict -map\
    [dict replace [namespace ensemble configure dict -map]\
                  getnull ::tcl::dict::getnull]
