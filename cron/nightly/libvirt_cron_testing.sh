#! /bin/sh

defaultsrcdir="/home/autotest/libvirt"
distdir="/tmp/libvirt_autotest_distdir"
autotestdir="/usr/local/autotest"
autotestcli=$autotestdir/cli
targetdir=$autotestdir/client/tests/libvirt_install

logfile="libvirt_autotest_distdir.log"
autogen="autogen.sh"
install_flag="/tmp/libvirt_install_success.tmp"
PYTHON="/usr/bin/python"
SSH="/usr/bin/ssh"

AUTOTEST_SERVER="http://10.66.7.19"
MACHINE=
TESTSUITS=
TESTNAME="libvirt_continuous_tesing"

source_dist()
{
    srcdir=$1
    shift

    autogen_f=$srcdir/$autogen
    echo "execute $autogen_f" | tee -a $logfile

    if [ ! -e $autogen_f ] || [ ! -x $autogen_f ]; then
        echo "autogen.sh in $srdir doesn't exist or couldn't be executed" | tee -a $logfile
        return 1
    else
        (cd $distdir
        $autogen_f
        if [ $? -ne 0 ]; then
            exit 1
        fi
        make dist
        if [ $? -ne 0 ]; then
            exit 1
        fi
        ) | tee -a $logfile
        if [ $? -ne 0 ]; then
            return 1
        fi
    fi

    return 0
}

git_pull()
{
    srcdir=$1
    shift

    if [ ! -d $srcdir/.git ]; then
        echo "$srcdir is not a git direcotry" | tee -a $logfile
        return 1
    else
        echo "cd $srcdir" | tee -a $logfile
        echo "running \"git pull\"..." | tee -a $logfile
        (cd $srcdir
         git pull) | tee -a $logfile

        if [  $? -ne 0 ]; then
            return 1
        fi
    fi

    return 0
}

dist_check()
{
    if ! ls $distdir/libvirt-*.tar.gz > /dev/null; then
        return 1
    fi
}

distribute()
{
    rm -rf $targetdir/libvirt-*.tar.gz
    if ! cp -f $distdir/libvirt-*.tar.gz $targetdir > /dev/null; then
        return 1
    fi
}

machine_check()
{
    local m=$1
    shift

    if ! ping -c 3 $m > /dev/null; then
        return 1
    fi
}

autotest_prepare()
{
    rm_auto_cmd="rm -rf $autotestdir"
    $SSH -l root $MACHINE $rm_auto_cmd | tee -a $logfile
    if [ $? -ne 0 ]; then
        return 1
    fi
}

submit_job()
{
    retval=0
    cli=$autotestcli/atest
    START_DATE=`date +%m/%d/%Y" "%T`
    echo "Job start at $START_DATE" | tee -a $logfile

    for testsuit in $(echo $TESTSUITS | tr "," "\n")
    do
        echo "Running: $PYTHON $cli job create -t $testsuit \
-m $MACHINE \"$TESTNAME($testsuit)\" --web=$AUTOTEST_SERVER" | tee -a $logfile
        ($PYTHON $cli job create \
                             -t $testsuit \
                             -m $MACHINE \
                             "$TESTNAME($testsuit)" \
                             --web=$AUTOTEST_SERVER
        ) | tee -a $logfile
        if [ $? -ne 0 ]; then
            echo "$testsuit submission Failed" | tee -a $logfile
            retval=1
            break
        fi
        echo "Success to submit job, job name is $TESTNAME($testsuit)" | tee -a $logfile

        echo "Checking job status:" | tee -a $logfile
        sleep_time=1
        while [ 1 ]
        do
            running_job=$($PYTHON $cli job list -r -u autotest --web=$AUTOTEST_SERVER | sed -n '$p')
            if [ -z "$running_job" ]; then
                result_state=$($PYTHON $cli job list -u autotest --web=$AUTOTEST_SERVER | sed -n '$p')
                echo "$testsuit :$result_state" | tee -a $logfile

                if echo $result_state | grep "Completed" > /dev/null; then
                    # sleep 10 secs for testing machine boot
                    echo "Waiting 1 min for testing machine reboot"
                    sleep 60
                    if $SSH -l root $MACHINE ls $install_flag > /dev/null; then
                        break
                    else
                        echo "Libvirt install testing FAIL!" | tee -a $logfile
                        retval=1
                        break 2
                    fi
                elif echo $result_state | grep "Failed" > /dev/null; then
                    retval=1
                    break 2
                fi
            else
                if [ $sleep_time -eq 1 ] && echo $running_job | grep "Running" > /dev/null; then
                    echo "$testsuit :$running_job" | tee -a $logfile
                    sleep_time=10
                fi
            fi
            sleep $sleep_time
        done
    done

    END_DATE=`date +%m/%d/%Y" "%T`
    echo "Job end at $END_DATE" | tee -a $logfile
    echo "$retval"
    return $retval
}

init()
{
   :>$logfile
   echo "Initiate testing environment" | tee -a $logfile
   echo "remove old $distdir" | tee -a $logfile
   rm -rf $distdir
   echo "make new $distdir" | tee -a $logfile
   mkdir $distdir
}

usage()
{
    echo "This is the cron script for libvirt testing.
          -d: the libvirt source directory in full path
          -t: specify testsuits to run  test1,test2,...
          -m: give the machine to run tests on
          -h: help"
}

###############################################################
# main
###############################################################
if [ $# -eq 0 ]; then
    usage
    exit 1
fi

while getopts :hd:m:t: option
do
    case "$option" in
    h)
        usage
        exit 1
        ;;
    d)
        srcdir=$OPTARG
        ;;
    m)
        MACHINE=$OPTARG
        ;;
    t)
        TESTSUITS=$OPTARG
        ;;
    *)
        echo "Invaid option"
        usage
        exit 1
        ;;
    esac
done

if [ -z $MACHINE ]; then
    echo "A host is required to run job"
    exit 1
fi
echo "The testing machine is $MACHINE"

if [ -z $TESTSUITS ]; then
    echo "A testsuit must be specified"
    exit 1
fi
echo "Testsuit is $TESTSUITS"

if ! machine_check $MACHINE; then
    echo "Failed to ping machine $MACHINE" | tee -a $logfile
    exit 1
fi

init

srcdir=${srcdir-$defaultsrcdir}
echo "Libvirt source code direcotry is $srcdir" | tee -a $logfile
echo "" >> $logfile

git_pull $srcdir
if [ $? -ne 0 ]; then
    echo "Failed to pull git update" | tee -a $logfile
    exit 1
fi
echo "Success to git pull" | tee -a $logfile
echo "" >> $logfile

echo "Make distribution..." | tee -a $logfile
source_dist $srcdir
if [ $? -ne 0 ]; then
    echo "Failed to make distribution" | tee -a $logfile
    exit 1
fi
echo "Success to make distribution" | tee -a $logfile
echo "" >> $logfile

if ! dist_check; then
    echo "No libvirt tarball is produced in $distdir" | tee -a $logfile
    exit 1
fi

echo "Copy libvirt tarball to $targetdir" | tee -a $logfile
if ! distribute; then
    echo "Failed to copy libvirt tarball to $targetdir" | tee -a $logfile
    exit 1
fi
echo "Done with copying libvirt tarball" | tee -a $logfile
echo "" >> $logfile

echo "Remove the old autotest on testing machine" | tee -a $logfile
if ! autotest_prepare; then
    echo "Failed to remove $autotestdir on machine $MACHINE" | tee -a $logfile
    exit 1
fi

echo "Success to remove $autotestdir on machine $MACHINE" | tee -a $logfile
echo "" >> $logfile

echo "Testsuit list: $TESTSUITS" | tee -a $logfile
submit_job
if [ $? -ne 0 ]; then
    exit 1
fi
echo ""

exit 0
