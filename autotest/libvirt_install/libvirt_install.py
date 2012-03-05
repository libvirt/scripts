import os, re, string

from autotest_lib.client.common_lib import error
from autotest_lib.client.bin import utils, test

class libvirt_install(test.test):
    """
    libvirt upstream compile & install testing
    """
    version = 1
    BUIDROOT = '/root/rpmbuild'
    success_flag = "/tmp/libvirt_install_success.tmp"
    def setup(self, tarball='libvirt-*.tar.gz'):
        tarpath = utils.unmap_url(self.bindir, tarball)
        for f in os.listdir(self.bindir):
            if re.match('libvirt-[0-9]', f):
                fpath = os.path.join(self.bindir, f)
                os.chown(fpath, 0, 0)

        output = os.path.join(self.resultsdir, 'compile.log')
        t_output = open(output, 'w')
        t_cmd = ('rpmbuild -ta %s ' % tarpath)
        try:
            cmd_result = utils.run(t_cmd, stdout_tee=t_output,
                                   stderr_tee=t_output)
        finally:
            t_output.close()

    def initialize(self):
        if os.path.exists(self.success_flag):
            os.unlink(self.success_flag)

    def run_once(self):
        RPMS_dir = os.path.join(self.BUIDROOT, "RPMS/x86_64")
        os.chdir(RPMS_dir)
        rpmballs = os.listdir(RPMS_dir)
        rpmstr = string.join(rpmballs, " ")
        rpm_install_cmd = "rpm -Uvh %s --force 2>&1" % rpmstr
        cmd_result = utils.system(rpm_install_cmd)
        if cmd_result != 0:
            raise error.TestFail("Libvirt RPM install FAIL")

        libvirtd_restart_cmd= "service libvirtd restart"
        cmd_result = utils.system(libvirtd_restart_cmd)
        if cmd_result != 0:
            raise error.TestFail("libvirtd restart FAIL")

        virsh_cmd = "virsh uri"
        cmd_result = utils.system(virsh_cmd)
        if cmd_result != 0:
            raise error.TestFail("virsh command FAIL")

        utils.system('touch %s' % self.success_flag)
