<style lang="scss" scoped>
@import "ozaria/site/styles/common/variables.scss";
@import "app/styles/ozaria/_ozaria-style-params.scss";
@import "app/styles/utils";
@if $is-ozaria {
  li {
    @include font-p-2-paragraph-medium-gray;
    color: $twilight;
    display: inline;

    a {
      text-decoration: underline;
    }
  }
  li:not(:first-child):before {
    content: " > ";
    color: $twilight;
    font-weight: bold;
  }
  li:last-child {
    color: #6D8392;
  }
}
@if $is-codecombat {
  * {
    color: #065e73;
  }
  li {
    display: inline;
  }
  li:not(:first-child):before {
    color: #000;
    content: " > ";
  }
}
</style>

<template>
    <div class="breadcrumbs rtl-allowed">
        <li v-for="link in links">
            <a v-if="link.href" :href="link.href" @click="$emit('click', link.text)">{{ link.i18n ? $t(link.i18n) : link.text }}</a>
            <span v-else-if="link.i18n">{{ $t(link.i18n) }}</span>
            <span v-else>{{ link.text }}</span>
        </li>
    </div>
</template>

<script>
  export default {
    props: {
      /**
      * Each item represents a link with either a href, i18n translated description or just plain text.
      * {Array} links
      * {?string} links.href: the location for the breadcrumb. Skip this to render the link as text and not a href.
      * {?string} links.i18n: the lookup value to use i18n as the display text
      * {?string} links.text: plain text to display instead of i18n
      */
      links: {
        type: Array,
        required: true,
        // Each object in the array must contain one of these values
        validator: (links) => _.every(links, (link) => link.href || link.i18n || link.text)
      }
    }
  }
</script>
