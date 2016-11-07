#    [qMp] firmware generator (http://qmp.cat)

#    Copyright (C) 2011-2016 Routek S.L. (http://routek.net)
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#    Contributors:
#	Pau Escrich <p4u@dabax.net>
#	Simó Albert i Beltran
#	Agustí Moll
#	Roger Pueyo Centelles

LEDE_SOURCE_CLONE = git clone http://git.lede-project.org/source.git
LEDE_PKG_CLONE = git clone  https://git.lede-project.org/feed/packages.git

QMP_GIT_RW = ssh://gitolite@dev.qmp.cat:qmp.git
QMP_GIT_RO = http://dev.qmp.cat/qmp.git
QMP_GIT_BRANCH ?= testing
QMP_CODENAME ?= Kalimotxo
QMP_RELEASE ?= trunk
QMP_FEED = package/feeds/qmp_packages

BUILD_DIR = build
CONFIG_DIR = configs
MY_CONFIGS = $(BUILD_DIR)/configs
IMAGES = images
SHELL = bash
SCRIPTS_DIR= scripts

J ?= 1
V ?= 0
TBUILD ?= lede

MAKE_SRC = -j$(J) V=$(V)

IMAGEOPT ?= true
VERSIONOPT ?= true
VERSION_REPO ?= http://downloads.lede-project.org/snapshots
VERSION_DIST ?= qMp
VERSION_NICK ?= Kalimotxo
VERSION_CODE ?= Kalimotxo
VERSION_NUMBER ?= trunk
COMMUNITY ?= qMp
EXTRA_PACKS =
DISTCL = `echo $(VERSION_DIST) | tr A-Z a-z`

include targets.mk

TIMESTAMP = $(shell date +%Y%m%d-%H%M)

#Checking if developer mode is enabled and if target is defined before
$(eval $(if $(DEV),QMP_GIT=$(QMP_GIT_RW),QMP_GIT=$(QMP_GIT_RO)))

#Define TARGET_CONFIGS and TARGET
$(eval $(if $(TARGET_MASTER),TARGET_CONFIGS=$(TARGET_MASTER),TARGET_CONFIGS=$(T)))
$(eval $(if $(T),,TARGET_CONFIGS=$(MPT)))
$(eval $(if $(TARGET),,TARGET=$(T)))
$(eval $(if $(MPTARGET),,MPTARGET=$(MPT)))

#Define BUILD_PATH based on TBUILD (defined in targets.mk)
$(eval $(if $(TBUILD),,TBUILD=$(TARGET)))
BUILD_PATH=$(BUILD_DIR)/$(TBUILD)

#Getting output image paths and names
IMAGE_PATH := $(shell echo bin/targets/$(ARCH)/$(SUBARCH)/$(FACTORY) | awk  '{print $$1}')
IM_NAME := $(shell echo $(IMAGE) | awk '{print $$2}')
SIMAGE_PATH := $(shell echo bin/targets/$(ARCH)/$(SUBARCH)/$(SYSUPGRADE) | awk '{print $$1}')
SIM_NAME := $(shell echo $(SYSUPGRADE) | awk '{print $$2}')

CONFIG = $(BUILD_PATH)/.config
KCONFIG = $(BUILD_PATH)/target/linux/$(ARCH)/config-*

.PHONY: checkout clean clean_qmp compile config kernel_menuconfig menuconfig list_archs list_targets post_build pre_build update

define build_src
	$(eval BRANCH_GIT=$(shell git --git-dir=$(BUILD_DIR)/qmp/.git branch|grep ^*|cut -d " " -f 2))
	$(eval REV_GIT=$(shell git --git-dir=$(BUILD_DIR)/qmp/.git --no-pager log -n 1 --oneline|cut -d " " -f 1))
	make -C $(BUILD_PATH) $(MAKE_SRC) IMAGEOPT=$(IMAGEOPT) VERSIONOPT=$(VERSIONOPT) VERSION_REPO=$(VERSION_REPO) VERSION_DIST=$(VERSION_DIST) VERSION_NICK=$(VERSION_NICK) VERSION_NUMBER=$(VERSION_NUMBER) VERSION_CODE=$(VERSION_CODE) BRANCH_GIT=$(BRANCH_GIT) REV_GIT=$(REV_GIT) QMP_CODENAME=$(QMP_CODENAME) QMP_RELEASE=$(QMP_RELEASE)
endef

define copy_feeds_file
	$(if $(1),$(eval FEEDS_DIR=$(1)),$(eval FEEDS_DIR=$(TBUILD)))
	$(if $(FEEDS_DIR),,$(call target_error))
	cp -f $(BUILD_DIR)/$(FEEDS_DIR)/feeds.conf.default $(BUILD_DIR)/$(FEEDS_DIR)/feeds.conf
	cat $(BUILD_DIR)/qmp/feeds.conf >> $(BUILD_DIR)/$(FEEDS_DIR)/feeds.conf
	sed -i -e "s|PATH|`pwd`/$(BUILD_DIR)|" $(BUILD_DIR)/$(FEEDS_DIR)/feeds.conf
endef

define checkout_src
	$(LEDE_SOURCE_CLONE) $(BUILD_PATH)
	mkdir -p dl
	ln -fs ../../dl $(BUILD_PATH)/dl
	ln -fs ../qmp/files $(BUILD_PATH)/files
	ln -fs $(BUILD_DIR)/qmp/files
	rm -rf $(BUILD_PATH)/feeds/
	$(call copy_feeds_file,$(TBUILD))
endef

define checkout_lede_pkg_override
	$(LEDE_PKG_CLONE) $(BUILD_DIR)/packages.$(TARGET)
	sed -i -e "s|src-link packages .*|src-link packages `pwd`/$(BUILD_DIR)/packages.$(TARGET)|" $(BUILD_PATH)/feeds.conf
endef

define copy_config
	$(if $(T), $(call copy_config_target),$(call copy_config_mptarget))
endef

define copy_config_mptarget
	@echo "Using multi-profile target $(MPT)"
	$(if $(T),@echo "Using multi-profile $(ARCH)-$(SUBARCH) for target $(T)", @echo "Using multi-profile $(MPT)")

	cp -f $(CONFIG_DIR)/$(ARCH)-$(SUBARCH)-multiprofile $(CONFIG) || echo "WARNING: Config file not found!"
	@for DEVICE in $(TINY); do \
		echo $(DEVPKG)$$DEVICE=\"$(TINYPKG)\" >> $(CONFIG) ;\
	done
	@for DEVICE in $(SMALL); do \
		echo $(DEVPKG)$$DEVICE=\"$(SMALLPKG)\" >> $(CONFIG) ; \
	done
	@for DEVICE in $(BIG); do \
		echo $(DEVPKG)$$DEVICE=\"$(BIGPKG)\" >> $(CONFIG) ; \
	done
	cd $(BUILD_PATH) && make defconfig
endef

define copy_config_target
	@echo "Using target $(T)"

	@#If the target is part of a multi-profile target, then switch to multi-profile compilation
   $(if $(MPNAME), \
		$(call copy_config_mptarget), \
		cp -f $(CONFIG_DIR)/$(PROFILE) $(CONFIG) || echo "WARNING: Config file not found!"; \
		-[ -f $(CONFIG_DIR)/targets/$(TARGET) ] && cat $(CONFIG_DIR)/targets/$(TARGET) >> $(CONFIG) || true; \
		cd $(BUILD_PATH) && make defconfig)
endef

define copy_config_obsolete
	@echo "Syncronizing new configuration"
	cp -f $(CONFIG_DIR)/$(TARGET_CONFIGS)/config $(CONFIG) || echo "WARNING: Config file not found!"
	cd $(BUILD_PATH) && ./scripts/diffconfig.sh > .config.tmp
	cp -f $(BUILD_PATH)/.config.tmp $(BUILD_PATH)/.config
	cd $(BUILD_PATH) && make defconfig
	-[ -f $(CONFIG_DIR)/$(TARGET_CONFIGS)/kernel_config ] && cat $(CONFIG_DIR)/$(TARGET_CONFIGS)/kernel_config >> $(CONFIG)
endef

define copy_myconfig
	@echo "Syncronizing configuration from previous one"
	@cp -f $(MY_CONFIGS)/$(TARGET_CONFIGS)/config $(CONFIG) || echo "WARNING: Config file not found in $(MY_CONFIGS)!"
	-@[ -f $(MY_CONFIGS)/$(TARGET_CONFIGS)/kernel_config ] && cat $(MY_CONFIGS)/$(TARGET_CONFIGS)/kernel_config >> $(CONFIG)
endef

define update_feeds
	@echo "Updating feed $(1)"
	./$(BUILD_DIR)/$(1)/scripts/feeds update -a

	./$(BUILD_DIR)/$(1)/scripts/feeds install -a
endef

define menuconfig_owrt
	make -C $(BUILD_PATH) menuconfig
	$(if $(T), mkdir -p $(MY_CONFIGS)/$(TARGET),mkdir -p $(MY_CONFIGS)/$(MPTARGET))
	$(if $(T), cp -f $(CONFIG) $(MY_CONFIGS)/$(TARGET)/config, cp -f $(CONFIG) $(MY_CONFIGS)/$(MPTARGET)/config)
endef

define kmenuconfig_owrt
	make -C $(BUILD_PATH) kernel_menuconfig
	mkdir -p $(MY_CONFIGS)/$(TARGET)
	cp -f $(KCONFIG) $(MY_CONFIGS)/$(TARGET)/kernel_config
endef

define pre_build
	@echo "Executing PRE_BUILD scripts"
	$(foreach SCRIPT, $(wildcard $(SCRIPTS_DIR)/*.script), $(shell $(SCRIPT) PRE_BUILD $(TBUILD) $(TARGET) $(EXTRA_PACKS)) )
endef

define post_build
	$(eval BRANCH_GIT=$(shell git --git-dir=$(BUILD_DIR)/qmp/.git branch|grep ^*|cut -d " " -f 2))
	$(if $(IM_NAME),,$(eval IM_NAME=$(COMMUNITY)_$(VERSION_NUMBER)-$(VERSION_NICK)_$(NAME)_factory_$(TIMESTAMP).bin))
	$(if $(SIM_NAM),,$(eval SIM_NAME=$(COMMUNITY)_$(VERSION_NUMBER)-$(VERSION_NICK)_$(NAME)_sysupgrade_$(TIMESTAMP).bin))
	$(eval COMP=$(shell ls $(BUILD_PATH)/$(IMAGE_PATH) 2>/dev/null | grep -c \\.gz))
	mkdir -p $(IMAGES)
	-@[ $(COMP) -eq 1 ] && gunzip $(BUILD_PATH)/$(IMAGE_PATH) -c > $(IMAGES)/$(IM_NAME)
	-@[ $(COMP) -ne 1 -a -f $(BUILD_PATH)/$(IMAGE_PATH) ] && cp -f $(BUILD_PATH)/$(IMAGE_PATH) $(IMAGES)/$(IM_NAME)
	-@[ $(COMP) -eq 1 -a -n "$(SYSUPGRADE)" ] && gunzip $(BUILD_PATH)/$(SIMAGE_PATH) -c > $(IMAGES)/$(SIM_NAME)
	-@[ $(COMP) -ne 1 -a -n "$(SYSUPGRADE)" ] && cp -f $(BUILD_PATH)/$(SIMAGE_PATH) $(IMAGES)/$(SIM_NAME)
	@[ -f $(IMAGES)/$(IM_NAME) ] || echo No output image configured in targets.mk
	@echo $(IM_NAME)
	$(if $(SYSUPGRADE),@echo $(SIM_NAME))
	@echo "Executing POST_BUILD scripts"
	$(foreach SCRIPT, $(wildcard $(SCRIPTS_DIR)/*.script), $(shell $(SCRIPT) POST_BUILD $(TBUILD) $(TARGET) $(EXTRA_PACKS)) )
	@echo "qMp firmware compiled, you can find output files in $(IMAGES) directory."
endef

define clean_all
	rm -rf $(BUILD_DIR)/*
	rm -f .checkout_*
	rm -f $(IMAGES)/*.bin $(IMAGES)/IMAGES
endef

define clean_target
	-rm -rf $(BUILD_PATH)
	-rm -f .checkout_$(TBUILD)
	-rm -rf $(BUILD_DIR)/packages.$(TARGET)
	rm -f .checkout_lede_pkg_override_$(TARGET)
endef

define clean_pkg
	echo "Cleaning package $1"
	make $1/clean
endef

define target_error
	@echo "You must specify either a single target, using the T variable (e.g.: make T=alix build),"
	@echo "or a multi-profile target, using the MPT variable (e.g.: make MPT=ar71xx-generic build),"
	@echo ""
	@echo "To see avialable targets run: make list_targets"
	@echo "To see avialable multi-profile target run: make list_mptargets"
	@exit 1
endef

define get_git_local_revision
	git rev-parse origin/$1
endef

define get_git_remote_revision
	git ls-remote origin $1 | awk 'NR==1{print $$1}'
endef

all: build

.checkout_qmp:
	git clone $(QMP_GIT) $(BUILD_DIR)/qmp
	cd $(BUILD_DIR)/qmp; git checkout $(QMP_GIT_BRANCH); cd ..
	@touch $@

.checkout_lede_pkg:
	$(LEDE_PKG_CLONE) $(BUILD_DIR)/packages
	@touch $@

.checkout_lede_pkg_override:
	$(if $(filter $(origin LEDE_PKG_CLONE),override),$(if $(wildcard .checkout_lede_pkg_override_$(TARGET)),,$(call checkout_lede_pkg_override)),)
	@touch .checkout_lede_pkg_override_$(TARGET)

.checkout_lede:
	$(if $(TBUILD),,$(call target_error))
	$(if $(wildcard .checkout_$(TBUILD)),,$(call checkout_src))

checkout: .checkout_qmp .checkout_lede .checkout_lede_pkg .checkout_lede_pkg_override
	$(if $(wildcard .checkout_$(TBUILD)),,$(call update_feeds,$(TBUILD)))
	$(if $(wildcard .checkout_$(TBUILD)),,$(call copy_config))
	@touch .checkout_$(TBUILD)

sync_config:
	$(if $(MPTARGET)$(TARGET),,$(call target_error))
	$(if $(wildcard $(MY_CONFIGS)/$(TARGET_CONFIGS)), $(call copy_myconfig),$(call copy_config))

update: .checkout_lede_pkg .checkout_lede_pkg_override .checkout_qmp
	$(if $(TBUILD),,$(call target_error))
	cd $(BUILD_DIR)/qmp && git pull
	$(call copy_feeds_file)

update_all: .checkout_lede_pkg .checkout_lede_pkg_override .checkout_qmp
	@echo Updating qMp repository
	cd $(BUILD_DIR)/qmp && git pull
	@echo Updating feeds config files
	$(foreach dir,$(TBUILD_LIST),$(if $(wildcard $(BUILD_DIR)/$(dir)),$(call copy_feeds_file,$(dir))))
	@echo Updating feeds
	$(foreach dir,$(TBUILD_LIST),$(if $(wildcard $(BUILD_DIR)/$(dir)),$(call update_feeds,$(dir))))

update_feeds: update
	$(call update_feeds,$(TBUILD))

menuconfig: checkout sync_config
	$(call menuconfig_owrt)

kernel_menuconfig: checkout sync_config
	$(call kmenuconfig_owrt)

clean:
	$(if $(TARGET),$(call clean_target),$(call clean_all))

clean_qmp:
	cd $(BUILD_PATH) ; \
	for d in $(QMP_FEED)/*; do make $$d/clean ; done

post_build: checkout
		$(call post_build)

pre_build: checkout
	$(call pre_build)

compile: checkout
	$(if $(MPTARGET),$(call build_src))

list_targets:
	$(info $(HW_AVAILABLE))
	@exit 0

list_mptargets:
		$(info $(MP_AVAILABLE))
		@exit 0

target_name:
	$(info $(NAME))
	@exit 0

config:
	@select HW in $(HW_AVAILABLE); do break; done; echo $$HW > .config.tmp;
	mv .config.tmp .config

help:
	-cat README | more

build: checkout sync_config pre_build compile post_build

is_up_to_date:
	cd $(BUILD_DIR)/qmp && test "$$($(call get_git_local_revision,$(QMP_GIT_BRANCH)))" == "$$($(call get_git_remote_revision,$(QMP_GIT_BRANCH)))"
