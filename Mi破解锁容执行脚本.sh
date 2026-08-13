#!/bin/sh
#本方法通过禁用30S关机服务，让1%电量再战2小时，实现变相解锁容，MT管理器以root权限执行即可#############
pm disable com.miui.securitycenter/com.miui.powercenter.provider.PowerSaveService
if [ $? -eq 0 ]
then
  	echo "
-----------------------------------------------------

                    破解锁容成功
                   
-----------------------------------------------------"
else
  	echo "
-----------------------------------------------------

                    破解锁容失败
                  
                 正在尝试重新破解……
                   
-----------------------------------------------------"
sleep 1
pm enable com.miui.securitycenter/com.miui.powercenter.provider.PowerSaveService
sleep 2
pm disable com.miui.securitycenter/com.miui.powercenter.provider.PowerSaveService
if [ $? -eq 0 ];then
echo "
-----------------------------------------------------

                    破解锁容成功
                   
-----------------------------------------------------"
else
echo "
-----------------------------------------------------

                    破解锁容失败
                   
           请尝试使用thanox禁用相关服务
           
-----------------------------------------------------"
fi
fi
echo "
         作者@Mi00005，遇到问题请酷安搜索🔍

-----------------------------------------------------"