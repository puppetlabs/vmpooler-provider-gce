# Changelog

## [1.2.0](https://github.com/puppetlabs/vmpooler-provider-gce/tree/1.2.0) (2023-08-10)

[Full Changelog](https://github.com/puppetlabs/vmpooler-provider-gce/compare/1.1.0...1.2.0)

**Implemented enhancements:**

- Bump jruby to 9.4.3.0 and update lockfile [\#31](https://github.com/puppetlabs/vmpooler-provider-gce/pull/31) ([yachub](https://github.com/yachub))

**Merged pull requests:**

- Bump thor from 1.2.1 to 1.2.2 [\#29](https://github.com/puppetlabs/vmpooler-provider-gce/pull/29) ([dependabot[bot]](https://github.com/apps/dependabot))

## [1.1.0](https://github.com/puppetlabs/vmpooler-provider-gce/tree/1.1.0) (2023-05-01)

[Full Changelog](https://github.com/puppetlabs/vmpooler-provider-gce/compare/1.0.0...1.1.0)

**Merged pull requests:**

- Migrate issue management to Jira [\#27](https://github.com/puppetlabs/vmpooler-provider-gce/pull/27) ([yachub](https://github.com/yachub))
- Bump jruby to 9.4.2.0 [\#26](https://github.com/puppetlabs/vmpooler-provider-gce/pull/26) ([yachub](https://github.com/yachub))
- Bump rack-test from 2.0.2 to 2.1.0 [\#24](https://github.com/puppetlabs/vmpooler-provider-gce/pull/24) ([dependabot[bot]](https://github.com/apps/dependabot))
- Update googleauth requirement from \>= 0.16.2, \< 1.3.0 to \>= 0.16.2, \< 1.4.0 [\#18](https://github.com/puppetlabs/vmpooler-provider-gce/pull/18) ([dependabot[bot]](https://github.com/apps/dependabot))

## [1.0.0](https://github.com/puppetlabs/vmpooler-provider-gce/tree/1.0.0) (2023-04-19)

[Full Changelog](https://github.com/puppetlabs/vmpooler-provider-gce/compare/0.5.0...1.0.0)

**Breaking changes:**

- \(RE-15124\) Decouple DNS Record Management into DNS Plugins [\#21](https://github.com/puppetlabs/vmpooler-provider-gce/pull/21) ([yachub](https://github.com/yachub))

## [0.5.0](https://github.com/puppetlabs/vmpooler-provider-gce/tree/0.5.0) (2023-03-06)

[Full Changelog](https://github.com/puppetlabs/vmpooler-provider-gce/compare/0.4.0...0.5.0)

**Implemented enhancements:**

- \(RE-15161\) Update to jruby-9.4.1.0 and move socket timeout to new method. [\#22](https://github.com/puppetlabs/vmpooler-provider-gce/pull/22) ([isaac-hammes](https://github.com/isaac-hammes))

**Merged pull requests:**

- Add docs and update actions [\#20](https://github.com/puppetlabs/vmpooler-provider-gce/pull/20) ([yachub](https://github.com/yachub))
- \(RE-15111\) Migrate Snyk to Mend Scanning [\#19](https://github.com/puppetlabs/vmpooler-provider-gce/pull/19) ([yachub](https://github.com/yachub))
- \(RE-14811\) Remove DIO as codeowners [\#17](https://github.com/puppetlabs/vmpooler-provider-gce/pull/17) ([yachub](https://github.com/yachub))
- Add Snyk action [\#16](https://github.com/puppetlabs/vmpooler-provider-gce/pull/16) ([yachub](https://github.com/yachub))
- Add release-engineering to codeowners [\#15](https://github.com/puppetlabs/vmpooler-provider-gce/pull/15) ([yachub](https://github.com/yachub))

## [0.4.0](https://github.com/puppetlabs/vmpooler-provider-gce/tree/0.4.0) (2022-07-27)

[Full Changelog](https://github.com/puppetlabs/vmpooler-provider-gce/compare/0.3.0...0.4.0)

**Merged pull requests:**

- \(maint\) Refactor cloud dns [\#13](https://github.com/puppetlabs/vmpooler-provider-gce/pull/13) ([sbeaulie](https://github.com/sbeaulie))
- Update googleauth requirement from \>= 0.16.2, \< 1.2.0 to \>= 0.16.2, \< 1.3.0 [\#12](https://github.com/puppetlabs/vmpooler-provider-gce/pull/12) ([dependabot[bot]](https://github.com/apps/dependabot))

## [0.3.0](https://github.com/puppetlabs/vmpooler-provider-gce/tree/0.3.0) (2022-06-21)

[Full Changelog](https://github.com/puppetlabs/vmpooler-provider-gce/compare/0.2.0...0.3.0)

**Merged pull requests:**

- release prep 0.3.0 [\#11](https://github.com/puppetlabs/vmpooler-provider-gce/pull/11) ([sbeaulie](https://github.com/sbeaulie))
- \(DIO-3162\) vmpooler gce provider to support disk type \(to use ssd\) [\#10](https://github.com/puppetlabs/vmpooler-provider-gce/pull/10) ([sbeaulie](https://github.com/sbeaulie))

## [0.2.0](https://github.com/puppetlabs/vmpooler-provider-gce/tree/0.2.0) (2022-04-19)

[Full Changelog](https://github.com/puppetlabs/vmpooler-provider-gce/compare/0.1.2...0.2.0)

**Implemented enhancements:**

- Set hostname for instance during create\_vm [\#8](https://github.com/puppetlabs/vmpooler-provider-gce/pull/8) ([yachub](https://github.com/yachub))

**Merged pull requests:**

- 0.2.0 release prep [\#9](https://github.com/puppetlabs/vmpooler-provider-gce/pull/9) ([yachub](https://github.com/yachub))
- Update vmpooler requirement from ~\> 1.3, \>= 1.3.0 to \>= 1.3.0, ~\> 2.3 [\#7](https://github.com/puppetlabs/vmpooler-provider-gce/pull/7) ([dependabot[bot]](https://github.com/apps/dependabot))
- Update googleauth requirement from ~\> 0.16.2 to \>= 0.16.2, \< 1.2.0 [\#6](https://github.com/puppetlabs/vmpooler-provider-gce/pull/6) ([dependabot[bot]](https://github.com/apps/dependabot))

## [0.1.2](https://github.com/puppetlabs/vmpooler-provider-gce/tree/0.1.2) (2022-01-10)

[Full Changelog](https://github.com/puppetlabs/vmpooler-provider-gce/compare/0.1.1...0.1.2)

## [0.1.1](https://github.com/puppetlabs/vmpooler-provider-gce/tree/0.1.1) (2022-01-10)

[Full Changelog](https://github.com/puppetlabs/vmpooler-provider-gce/compare/0.1.0...0.1.1)

## [0.1.0](https://github.com/puppetlabs/vmpooler-provider-gce/tree/0.1.0) (2022-01-10)

[Full Changelog](https://github.com/puppetlabs/vmpooler-provider-gce/compare/588e29b6e100327336bf0910ae16b6a85ffe279a...0.1.0)

**Merged pull requests:**

- Adding the cloud DNS API library and related methods [\#4](https://github.com/puppetlabs/vmpooler-provider-gce/pull/4) ([sbeaulie](https://github.com/sbeaulie))
- fix simplecov with jruby, add a .rubocop.yml config file [\#3](https://github.com/puppetlabs/vmpooler-provider-gce/pull/3) ([sbeaulie](https://github.com/sbeaulie))
- Add a release workflow for pushing to Rubygems [\#1](https://github.com/puppetlabs/vmpooler-provider-gce/pull/1) ([genebean](https://github.com/genebean))



\* *This Changelog was automatically generated by [github_changelog_generator](https://github.com/github-changelog-generator/github-changelog-generator)*
